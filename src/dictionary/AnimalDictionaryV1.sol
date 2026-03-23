// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {khaaliDictionaryV1} from "./khaaliDictionaryV1.sol";

/// @title AnimalDictionaryV1
/// @notice On-chain dictionary of animal names for khaaliNamesV1
contract AnimalDictionaryV1 is khaaliDictionaryV1 {
    bytes32 public constant NAME = keccak256("khaaliNamesV1_AnimalDictionaryV1");
    constructor(address data) khaaliDictionaryV1(data, 350) {}
}