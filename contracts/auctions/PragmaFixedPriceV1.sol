// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IPragmaHub.sol";

contract PragmaFixedPriceV1 is ReentrancyGuard {
  event PricePerTokenInWeiUpdated(
    uint256 indexed _projectId,
    uint256 indexed _pricePerTokenInWei
  );

  error MaxMintsReached();
  error InvalidProject();
  error InvalidTokenId();
  error PausedProject();
  error NotAllowed();

  IPragmaHub public immutable pragmaHubContract;

  string public constant minterType = "PragmaFixedPriceV1";

  uint256 private constant SEED = 1_000_000;

  // Keep track of mints per wallet
  mapping(address => mapping(uint256 => uint256)) public projectMintCounter;
  mapping(uint256 => uint256) public projectMintLimit;

  // Keep track of mints per project
  mapping(uint256 => bool) public projectMaxHasBeenMinted;
  mapping(uint256 => uint256) public projectMaxMints;

  // Price
  mapping(uint256 => uint256) private projectIdToPricePerTokenInWei;
  mapping(uint256 => bool) private projectIdToPriceIsConfigured;

  modifier onlyHubWhitelisted() {
    if (!pragmaHubContract.whitelist(msg.sender)) revert NotAllowed();
    _;
  }

  modifier onlyArtist(uint256 _projectId) {
    if (msg.sender != pragmaHubContract.projectIdToArtistAddress(_projectId))
      revert NotAllowed();
    _;
  }

  constructor(address _pragmaHubAddress) ReentrancyGuard() {
    pragmaHubContract = IPragmaHub(_pragmaHubAddress);
  }

  function updatePricePerTokenInWei(
    uint256 _projectId,
    uint256 _pricePerTokenInWei
  ) external onlyArtist(_projectId) {
    projectIdToPricePerTokenInWei[_projectId] = _pricePerTokenInWei;
    projectIdToPriceIsConfigured[_projectId] = true;
    emit PricePerTokenInWeiUpdated(_projectId, _pricePerTokenInWei);
  }

  function setProjectMintLimit(uint256 _projectId, uint8 _limit)
    public
    onlyHubWhitelisted
  {
    projectMintLimit[_projectId] = _limit;
  }

  function setProjectMaxMints(uint256 _projectId) public onlyHubWhitelisted {
    uint256 maxMints;
    uint256 mints;
    (, mints, maxMints, , , ) = pragmaHubContract.projectInfo(_projectId);
    projectMaxMints[_projectId] = maxMints;

    if (mints < maxMints) {
      projectMaxHasBeenMinted[_projectId] = false;
    }
  }

  function purchase(uint256 _projectId)
    public
    payable
    returns (uint256 _tokenId)
  {
    return purchaseTo(msg.sender, _projectId);
  }

  function purchaseTo(address _to, uint256 _projectId)
    public
    payable
    nonReentrant
    returns (uint256 _tokenId)
  {
    // max amount of mints have been minted
    if (projectMaxHasBeenMinted[_projectId]) revert MaxMintsReached();

    // if we have a mint limit
    if (projectMintLimit[_projectId] > 0) {
      if (
        projectMintCounter[msg.sender][_projectId] <
        projectMintLimit[_projectId]
      ) {
        projectMintCounter[msg.sender][_projectId]++;
      } else {
        revert MaxMintsReached();
      }
    }

    // make sure your price is configured
    if (!projectIdToPriceIsConfigured[_projectId]) revert NotAllowed();

    // make sure the payment equals the price
    if (msg.value < projectIdToPricePerTokenInWei[_projectId])
      revert NotAllowed();

    // token id
    uint256 tokenId = pragmaHubContract.mint(_to, _projectId, msg.sender);

    if (
      projectMaxMints[_projectId] > 0 &&
      tokenId % SEED == projectMaxMints[_projectId] - 1
    ) {
      projectMaxHasBeenMinted[_projectId] = true;
    }

    _splitFunds(_projectId);

    return tokenId;
  }

  function _splitFunds(uint256 _projectId) internal {
    if (msg.value > 0) {
      uint256 pricePerTokenInWei = projectIdToPricePerTokenInWei[_projectId];

      uint256 refund = msg.value - pricePerTokenInWei;
      if (refund > 0) {
        (bool _success, ) = msg.sender.call{value: refund}("");
        require(_success, "Refund failed");
      }

      uint256 treasuryAmount = (pricePerTokenInWei *
        pragmaHubContract.treasuryPercentage()) / 100;

      if (treasuryAmount > 0) {
        (bool success_, ) = pragmaHubContract.treasuryAddress().call{
          value: treasuryAmount
        }("");
        require(success_, "Treasury payment failed");
      }

      uint256 projectFunds = pricePerTokenInWei - treasuryAmount;
      uint256 additionalPayeeAmount;

      if (
        pragmaHubContract.projectIdToAdditionalPayeePercentage(_projectId) > 0
      ) {
        additionalPayeeAmount =
          (projectFunds *
            pragmaHubContract.projectIdToAdditionalPayeePercentage(
              _projectId
            )) /
          100;

        if (additionalPayeeAmount > 0) {
          (bool success_, ) = pragmaHubContract
            .projectIdToAdditionalPayee(_projectId)
            .call{value: additionalPayeeAmount}("");

          require(success_, "Additional payment failed");
        }
      }

      uint256 creatorFunds = projectFunds - additionalPayeeAmount;
      if (creatorFunds > 0) {
        (bool success_, ) = pragmaHubContract
          .projectIdToArtistAddress(_projectId)
          .call{value: creatorFunds}("");
        require(success_, "Artist payment failed");
      }
    }
  }

  function getPriceInfo(uint256 _projectId)
    external
    view
    returns (
      bool isConfigured,
      uint256 tokenPriceInWei,
      string memory currencySymbol,
      address currencyAddress
    )
  {
    isConfigured = projectIdToPriceIsConfigured[_projectId];
    tokenPriceInWei = projectIdToPricePerTokenInWei[_projectId];
    currencySymbol = "MATIC";
    currencyAddress = address(0);
  }
}
