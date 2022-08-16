// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPragmaHub.sol";

contract PragmaDutchAuctionV1 is ReentrancyGuard, Ownable {
  // Auction details updated for project `projectId`
  event SetAuctionDetails (
    uint256 indexed _projectId,
    uint256 _auctionTimestampStart,
    uint256 _auctionTimestampEnd,
    uint256 _startPrice,
    uint256 _basePrice
  );

  /// Auction details cleared for project `projectId`.
  event ResetAuctionDetails(uint256 indexed projectId);

  /// Minimum allowed auction length updated
  event MinAuctionLengthSecondsUpdated(
    uint256 _minAuctionLengthSeconds
  );

  error MaxMintsReached();
  error InvalidProject();
  error InvalidTokenId();
  error PausedProject();
  error NotAllowed();

  IPragmaHub public immutable pragmaHubContract;

  string public constant minterType = "DutchAuctionV1";

  uint256 private constant SEED = 1_000_000;

  // Keep track of mints per project
  mapping(uint256 => bool) public projectMaxHasBeenMinted;
  mapping(uint256 => uint256) public projectMaxMints;

  uint256 public minAuctionLengthSeconds = 3600;

  // projectId => auction settings
  mapping(uint256 => AuctionParams) public projectAuctionSettings;
  struct AuctionParams {
    uint256 timestampStart;
    uint256 timestampEnd;
    uint256 startPrice;
    uint256 basePrice;
  }

  modifier onlyHubWhitelisted() {
    if (!pragmaHubContract.whitelist(_msgSender())) revert NotAllowed();
    _;
  }

  modifier onlyArtist(uint256 _projectId) {
    if (_msgSender() != pragmaHubContract.projectIdToArtistAddress(_projectId))
      revert NotAllowed();
    _;
  }

  constructor(address _pragmaHubAddress) ReentrancyGuard() {
    pragmaHubContract = IPragmaHub(_pragmaHubAddress);
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

  // set the minimum auction lengt in seconds
  function setMinAuctionLengthSeconds(uint256 _minAuctionLengthSeconds) external onlyHubWhitelisted {
    minAuctionLengthSeconds = _minAuctionLengthSeconds;
    emit MinAuctionLengthSecondsUpdated(_minAuctionLengthSeconds);
  }

  function setAuctionDetails(
    uint256 _projectId,
    uint256 _auctionTimestampStart,
    uint256 _auctionTimestampEnd,
    uint256 _startPrice,
    uint256 _basePrice
  ) external onlyArtist(_projectId) {
    AuctionParams memory auctionParams = projectAuctionSettings[_projectId];

    require(auctionParams.timestampStart == 0 || block.timestamp < auctionParams.timestampStart, "Can't modify mid-auction");

    require(block.timestamp < _auctionTimestampStart, "Only future timestamps");

    require(_auctionTimestampEnd > _auctionTimestampStart, "Auction end must be greater than auction start");

    require(_auctionTimestampEnd >= _auctionTimestampStart + minAuctionLengthSeconds, "Auction length must be at least minimum auction lengt in seconds");

    require(_startPrice > _basePrice, "Auction start price must be greater than the auction end price");

    projectAuctionSettings[_projectId] = AuctionParams(
      _auctionTimestampStart,
      _auctionTimestampEnd,
      _startPrice,
      _basePrice
    );

    emit SetAuctionDetails(
      _projectId,
      _auctionTimestampStart,
      _auctionTimestampEnd,
      _startPrice,
      _basePrice
    );
  }

  function resetAuctionDetails(uint256 _projectId) external onlyHubWhitelisted {
    delete projectAuctionSettings[_projectId];
    emit ResetAuctionDetails(_projectId);
  }

  function purchase(uint256 _projectId) public payable returns (uint256 _tokenId) {
    return purchaseTo(_msgSender(), _projectId);
  }

  function purchaseTo(address _to, uint256 _projectId)
    public
    payable
    nonReentrant returns (uint256 _tokenId) {
      if (projectMaxHasBeenMinted[_projectId]) revert MaxMintsReached();

      uint256 currentPriceInWei = _getPrice(_projectId);
      if (msg.value < currentPriceInWei) revert NotAllowed();

      uint256 tokenId = pragmaHubContract.mint(_to, _projectId, _msgSender());

      if (
        projectMaxMints[_projectId] > 0 &&
        tokenId % SEED == projectMaxMints[_projectId] - 1
      ) {
        projectMaxHasBeenMinted[_projectId] = true;
      }

      _splitFunds(_projectId, currentPriceInWei);

      return tokenId;
  }

  function _splitFunds(uint256 _projectId, uint256 _currentPriceInWei) internal {
    if (msg.value > 0) {
      uint256 refund = msg.value - _currentPriceInWei;

      if (refund > 0) {
        (bool success_,) = msg.sender.call{value: refund}("");
        require(success_, "Refund failed");
      }

      uint256 treasuryAmount = (_currentPriceInWei *
        pragmaHubContract.treasuryPercentage()) / 100;
      if (treasuryAmount > 0) {
        (bool success_, ) = pragmaHubContract.treasuryAddress().call{
          value: treasuryAmount
        }("");
        require(success_, "Treasury payment failed");
      }

      uint256 projectFunds = _currentPriceInWei - treasuryAmount;
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

  function _getPrice(uint256 _projectId) private view returns (uint256) {
    AuctionParams memory auctionParams = projectAuctionSettings[_projectId];

    require(block.timestamp > auctionParams.timestampStart, "auction not yet started");

    if (block.timestamp >= auctionParams.timestampEnd) {
      require(auctionParams.timestampEnd > 0, "Only configured auctions");
      return auctionParams.basePrice;
    }

    uint256 elapsedTime = block.timestamp - auctionParams.timestampStart;
    uint256 duration = auctionParams.timestampEnd - auctionParams.timestampStart;
    uint256 startToEndDifference = auctionParams.startPrice - auctionParams.basePrice;

    return auctionParams.startPrice - ((elapsedTime * startToEndDifference) / duration);
  }

  function getPriceInfo(uint256 _projectId) external view returns (
    bool isConfigured,
    uint256 tokenPriceInWei,
    string memory currencySymbol,
    address currencyAddress
  ) {

    AuctionParams memory auctionParams = projectAuctionSettings[_projectId];

    isConfigured = (auctionParams.startPrice > 0);

    if (block.timestamp <= auctionParams.timestampStart) {
      tokenPriceInWei = auctionParams.startPrice;
    } else if (auctionParams.timestampEnd == 0) {
      tokenPriceInWei = 0;
    } else {
      tokenPriceInWei = _getPrice(_projectId);
    }

    currencySymbol = "MATIC";
    currencyAddress = address(0);
  }
}
