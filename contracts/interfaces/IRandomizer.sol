// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRandomizer {
  function value() external view returns (bytes32);
}
