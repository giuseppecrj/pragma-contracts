// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPragmaHub {
  event Mint(address indexed _to, uint256 indexed _tokenId);
  event ProxyUpdated(address indexed _minter);

  function nextProjectId() external view returns (uint256);

  function tokenIdToProjectId(uint256 _tokenId)
    external
    pure
    returns (uint256 _projectId);

  function whitelist(address minter) external view returns (bool);

  function projectIdToArtistAddress(uint256 _projectId)
    external
    view
    returns (address payable);

  function projectIdToAdditionalPayee(uint256 _projectId)
    external
    view
    returns (address payable);

  function projectIdToAdditionalPayeePercentage(uint256 _projectId)
    external
    view
    returns (uint256);

  function projectInfo(uint256 _projectId)
    external
    view
    returns (
      address,
      uint256,
      uint256,
      bool,
      address,
      uint256
    );

  function treasuryAddress() external view returns (address payable);

  function treasuryPercentage() external view returns (uint256);

  function getRoyaltyData(uint256 _tokenId)
    external
    view
    returns (
      address artistAddress,
      address additionalPayee,
      uint256 additionalPayeePercentage,
      uint256 royaltyFeeByID
    );

  function mint(
    address _to,
    uint256 _projectId,
    address _by
  ) external returns (uint256 tokenId);
}
