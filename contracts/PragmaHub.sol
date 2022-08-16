// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IRandomizer.sol";
import "./interfaces/IPragmaHub.sol";
import "./ContextMixin.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PragmaHub is ERC721Enumerable, ContextMixin, Ownable, IPragmaHub {
  error MaxMintsReached();
  error InvalidProject();
  error InvalidTokenId();
  error PausedProject();
  error NotAllowed();

  // randomizer contract
  IRandomizer public randomizer;

  struct Project {
    string name;
    string artist;
    string description;
    string website;
    string license;
    string baseURI;
    uint256 mints;
    uint256 maxMints;
    string metadata;
    mapping(uint256 => string) scripts;
    uint256 scriptCount;
    string ipfsHash;
    bool active;
    bool locked;
    bool paused;
  }

  /**
    Constants
  */
  address payable public treasuryAddress;
  uint256 public treasuryPercentage = 10;

  uint256 constant SEED = 1_000_000;
  uint256 public nextProjectId = 0;

  /**
    Mappings
  */
  mapping(uint256 => Project) projects;
  mapping(address => bool) public whitelist;
  mapping(address => bool) public minterWhitelist;
  mapping(uint256 => string) private tokenURIs;

  mapping(uint256 => bytes32) public tokenIdToHash;
  mapping(uint256 => address payable) public projectIdToArtistAddress;
  mapping(uint256 => address payable) public projectIdToAdditionalPayee;
  mapping(uint256 => uint256) public projectIdToAdditionalPayeePercentage;
  mapping(uint256 => uint256)
    public projectIdToSecondaryMarketRoyaltyPercentage;

  /**
    Modifiers
  */
  // Only valid ids
  modifier onlyValidTokenId(uint256 _tokenId) {
    if (!_exists(_tokenId)) revert InvalidTokenId();
    _;
  }

  // Only addresses in the whitelist
  modifier onlyWhitelist() {
    if (!whitelist[_msgSender()]) revert NotAllowed();
    _;
  }

  // Only projects that are unlocked
  modifier onlyUnlocked(uint256 _projectId) {
    if (projects[_projectId].locked) revert NotAllowed();
    _;
  }

  // Only artist of a specific project
  modifier onlyArtist(uint256 _projectId) {
    if (_msgSender() != projectIdToArtistAddress[_projectId])
      revert NotAllowed();
    _;
  }

  // Only whitelisted or artists
  modifier onlyArtistOrWhitelisted(uint256 _projectId) {
    if (
      !whitelist[_msgSender()] &&
      _msgSender() != projectIdToArtistAddress[_projectId]
    ) revert NotAllowed();
    _;
  }

  /**
    Core
  */
  constructor(
    string memory _name,
    string memory _symbol,
    address _randomizer
  ) ERC721(_name, _symbol) {
    whitelist[owner()] = true;
    treasuryAddress = payable(owner());
    randomizer = IRandomizer(_randomizer);
  }

  /** Overrides */
  function _msgSender() internal view override returns (address sender) {
    return ContextMixin.msgSender();
  }

  /**
    Minting
  */
  function mint(
    address _to,
    uint256 _projectId,
    address _by
  ) external returns (uint256 tokenId) {
    if (!minterWhitelist[_msgSender()]) revert NotAllowed();
    if (projects[_projectId].mints >= projects[_projectId].maxMints)
      revert MaxMintsReached();

    require(
      projects[_projectId].active ||
        _by == projectIdToArtistAddress[_projectId],
      "InvalidProject()"
    );

    require(
      !projects[_projectId].paused ||
        _by == projectIdToArtistAddress[_projectId],
      "PausedProject()"
    );

    return _mintToken(_to, _projectId);
  }

  function _mintToken(address _to, uint256 _projectId)
    internal
    returns (uint256 _tokenId)
  {
    uint256 nextTokenId = (_projectId * SEED) + projects[_projectId].mints;
    projects[_projectId].mints++;

    bytes32 tokenHash = keccak256(
      abi.encodePacked(
        projects[_projectId].mints,
        blockhash(block.number - 1),
        randomizer.value()
      )
    );

    tokenIdToHash[nextTokenId] = tokenHash;

    _safeMint(_to, nextTokenId);

    emit Mint(_to, nextTokenId);

    return nextTokenId;
  }

  /**
    Setters
  */

  /**
    Admin
  */
  function updateTreasuryAddress(address payable _treasuryAddress)
    public
    onlyOwner
  {
    treasuryAddress = _treasuryAddress;
  }

  function updateTreasuryPercentage(uint256 _treasuryPercentage)
    public
    onlyOwner
  {
    if (_treasuryPercentage >= 25) revert NotAllowed();
    treasuryPercentage = _treasuryPercentage;
  }

  function addWhitelisted(address _address) public onlyOwner {
    whitelist[_address] = true;
  }

  function removeWhitelisted(address _address) public onlyOwner {
    whitelist[_address] = false;
  }

  function addMintWhitelisted(address _address) public onlyOwner {
    minterWhitelist[_address] = true;
  }

  function removeMintWhitelisted(address _address) public onlyOwner {
    minterWhitelist[_address] = false;
  }

  function updateRandomizerAddress(address _randomizerAddress)
    public
    onlyWhitelist
  {
    randomizer = IRandomizer(_randomizerAddress);
  }

  /**
    Project
  */
  function addProject(
    string memory _projectName,
    address payable _artistAddress
  ) public onlyWhitelist returns (uint256 _projectId) {
    uint256 projectId = nextProjectId;

    projectIdToArtistAddress[projectId] = _artistAddress;
    projects[projectId].name = _projectName;
    projects[projectId].paused = true;
    projects[projectId].maxMints = SEED;

    nextProjectId++;

    return projectId;
  }

  function publish(
    uint256 _projectId,
    string memory _description,
    string memory _artistName,
    string memory _website,
    string memory _license,
    string memory _baseURI
  ) public onlyArtistOrWhitelisted(_projectId) {
    projects[_projectId].description = _description;
    projects[_projectId].artist = _artistName;
    projects[_projectId].website = _website;
    projects[_projectId].license = _license;
    projects[_projectId].baseURI = _baseURI;
  }

  function toggleProjectIsActive(uint256 _projectId) public onlyWhitelist {
    projects[_projectId].active = !projects[_projectId].active;
  }

  function toggleProjectIsLocked(uint56 _projectId)
    public
    onlyWhitelist
    onlyUnlocked(_projectId)
  {
    projects[_projectId].locked = true;
  }

  function toggleProjectIsPaused(uint256 _projectId)
    public
    onlyArtist(_projectId)
  {
    projects[_projectId].paused = !projects[_projectId].paused;
  }

  /**
    Artist
  */
  function updateProjectArtistAddress(
    uint256 _projectId,
    address payable _artistAddress
  ) public onlyArtistOrWhitelisted(_projectId) {
    projectIdToArtistAddress[_projectId] = _artistAddress;
  }

  function updateProjectName(uint256 _projectId, string memory _projectName)
    public
    onlyUnlocked(_projectId)
    onlyArtistOrWhitelisted(_projectId)
  {
    projects[_projectId].name = _projectName;
  }

  function updateProjectArtistName(
    uint256 _projectId,
    string memory _artistName
  ) public onlyUnlocked(_projectId) onlyArtistOrWhitelisted(_projectId) {
    projects[_projectId].artist = _artistName;
  }

  function updateProjectDescription(
    uint256 _projectId,
    string memory _description
  ) public onlyArtist(_projectId) {
    projects[_projectId].description = _description;
  }

  function updateProjectWebsite(uint256 _projectId, string memory _website)
    public
    onlyArtist(_projectId)
  {
    projects[_projectId].website = _website;
  }

  function updateProjectLicense(uint256 _projectId, string memory _license)
    public
    onlyArtist(_projectId)
  {
    projects[_projectId].license = _license;
  }

  function updateProjectBaseURI(uint256 _projectId, string memory _baseURI)
    public
    onlyUnlocked(_projectId)
    onlyArtistOrWhitelisted(_projectId)
  {
    projects[_projectId].baseURI = _baseURI;
  }

  function updateProjectAdditionalPayee(
    uint256 _projectId,
    address payable _additionalPayee,
    uint256 _additionalPayeePercentage
  ) public onlyArtist(_projectId) {
    if (_additionalPayeePercentage > 100) revert NotAllowed();
    projectIdToAdditionalPayee[_projectId] = _additionalPayee;
    projectIdToAdditionalPayeePercentage[
      _projectId
    ] = _additionalPayeePercentage;
  }

  function updateProjectSecondaryMarketRoyaltyPercentage(
    uint256 _projectId,
    uint256 _secondMarketRoyalty
  ) public onlyArtist(_projectId) {
    if (_secondMarketRoyalty > 100) revert NotAllowed();
    projectIdToSecondaryMarketRoyaltyPercentage[
      _projectId
    ] = _secondMarketRoyalty;
  }

  function updateProjectMaxMints(uint256 _projectId, uint256 _maxMints)
    public
    onlyArtist(_projectId)
  {
    require(
      (!projects[_projectId].locked ||
        _maxMints < projects[_projectId].maxMints),
      "Only if unlocked"
    );

    if (_maxMints < projects[_projectId].mints) revert NotAllowed();
    if (_maxMints >= SEED) revert NotAllowed();
    projects[_projectId].maxMints = _maxMints;
  }

  function addProjectScript(uint256 _projectId, string memory _script)
    public
    onlyUnlocked(_projectId)
    onlyArtistOrWhitelisted(_projectId)
  {
    projects[_projectId].scripts[projects[_projectId].scriptCount] = _script;
    projects[_projectId].scriptCount = projects[_projectId].scriptCount + 1;
  }

  function updateProjectScript(
    uint256 _projectId,
    uint256 _scriptId,
    string memory _script
  ) public onlyUnlocked(_projectId) onlyArtistOrWhitelisted(_projectId) {
    if (_scriptId > projects[_projectId].scriptCount) revert NotAllowed();
    projects[_projectId].scripts[_scriptId] = _script;
  }

  function removeProjectLastScript(uint256 _projectId)
    public
    onlyUnlocked(_projectId)
    onlyArtistOrWhitelisted(_projectId)
  {
    if (projects[_projectId].scriptCount < 0) revert NotAllowed();
    delete projects[_projectId].scripts[projects[_projectId].scriptCount - 1];
    projects[_projectId].scriptCount = projects[_projectId].scriptCount - 1;
  }

  function updateProjectMetadata(uint256 _projectId, string memory _metadata)
    public
    onlyUnlocked(_projectId)
    onlyArtistOrWhitelisted(_projectId)
  {
    projects[_projectId].metadata = _metadata;
  }

  function updateProjectIpfsHash(uint256 _projectId, string memory _ipfsHash)
    public
    onlyUnlocked(_projectId)
    onlyArtistOrWhitelisted(_projectId)
  {
    projects[_projectId].ipfsHash = _ipfsHash;
  }

  function updateProjectTokenURI(
    uint256 _projectId,
    uint256 _tokenId,
    string memory _tokenURI
  ) public onlyUnlocked(_projectId) onlyArtistOrWhitelisted(_projectId) {
    if (!_exists(_tokenId)) revert NotAllowed();
    tokenURIs[_tokenId] = _tokenURI;
  }

  /**
    Getters
  */
  function projectDetails(uint256 _projectId)
    public
    view
    returns (
      string memory projectName,
      string memory artist,
      string memory description,
      string memory website,
      string memory license
    )
  {
    projectName = projects[_projectId].name;
    artist = projects[_projectId].artist;
    description = projects[_projectId].description;
    website = projects[_projectId].website;
    license = projects[_projectId].license;
  }

  function projectInfo(uint256 _projectId)
    external
    view
    returns (
      address artistAddress,
      uint256 mints,
      uint256 maxMints,
      bool active,
      address additionalPayee,
      uint256 additionalPayeePercentage
    )
  {
    artistAddress = projectIdToArtistAddress[_projectId];
    mints = projects[_projectId].mints;
    maxMints = projects[_projectId].maxMints;
    active = projects[_projectId].active;
    additionalPayee = projectIdToAdditionalPayee[_projectId];
    additionalPayeePercentage = projectIdToAdditionalPayeePercentage[
      _projectId
    ];
  }

  function projectScriptInfo(uint256 _projectId)
    external
    view
    returns (
      string memory metadata,
      uint256 scriptCount,
      string memory ipfsHash,
      bool locked,
      bool paused
    )
  {
    metadata = projects[_projectId].metadata;
    scriptCount = projects[_projectId].scriptCount;
    ipfsHash = projects[_projectId].ipfsHash;
    locked = projects[_projectId].locked;
    paused = projects[_projectId].paused;
  }

  function projectScriptByIndex(uint256 _projectId, uint256 _index)
    external
    view
    returns (string memory)
  {
    return projects[_projectId].scripts[_index];
  }

  function projectURIInfo(uint256 _projectId)
    external
    view
    returns (string memory baseURI)
  {
    baseURI = projects[_projectId].baseURI;
  }

  function tokenIdToProjectId(uint256 _tokenId)
    external
    pure
    returns (uint256 _projectId)
  {
    return _tokenId / SEED;
  }

  function getRoyaltyData(uint256 _tokenId)
    public
    view
    returns (
      address artistAddress,
      address additionalPayee,
      uint256 additionalPayeePercentage,
      uint256 royaltyFeeByID
    )
  {
    uint256 projectId = _tokenId / SEED;
    artistAddress = projectIdToArtistAddress[projectId];
    additionalPayee = projectIdToAdditionalPayee[projectId];
    additionalPayeePercentage = projectIdToAdditionalPayeePercentage[projectId];
    royaltyFeeByID = projectIdToSecondaryMarketRoyaltyPercentage[projectId];
  }

  function tokenURI(uint256 _tokenId)
    public
    view
    override
    onlyValidTokenId(_tokenId)
    returns (string memory)
  {
    _requireMinted(_tokenId);

    string memory _tokenURI = tokenURIs[_tokenId];

    if (bytes(_tokenURI).length > 0) {
      return _tokenURI;
    }

    return
      string(
        abi.encodePacked(
          projects[_tokenId / SEED].baseURI,
          Strings.toString(_tokenId)
        )
      );
  }

  function _burn(uint256 tokenId) internal virtual override {
    super._burn(tokenId);

    if (bytes(tokenURIs[tokenId]).length != 0) {
      delete tokenURIs[tokenId];
    }
  }

  function isApprovedForAll(address _owner, address _operator)
    public
    view
    override
    returns (bool isOperator)
  {
    // if OpenSea's ERC721 Proxy Address is detected, auto-return true
    // for Polygon's Mumbai testnet, use 0xff7Ca10aF37178BdD056628eF42fD7F799fAc77c
    if (block.chainid == 80001) {
      if (_operator == address(0xff7Ca10aF37178BdD056628eF42fD7F799fAc77c)) {
        return true;
      }
    } else {
      if (_operator == address(0x58807baD0B376efc12F5AD86aAc70E78ed67deaE)) {
        return true;
      }
    }

    // otherwise, use the default ERC721.isApprovedForAll()
    return ERC721.isApprovedForAll(_owner, _operator);
  }
}
