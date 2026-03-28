// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {khaaliDictionaryV1} from "./khaaliDictionaryV1.sol";

/// @title AdjectiveDictionaryV1
/// @notice On-chain dictionary of adjective names for khaaliNamesV1
contract AdjectiveDictionaryV1 is khaaliDictionaryV1 {
    bytes32 public constant NAME = keccak256("khaaliNamesV1_AdjectiveDictionaryV1");
    constructor(address data) khaaliDictionaryV1(data, 1200) {}
}