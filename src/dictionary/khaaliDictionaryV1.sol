// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IkhaaliDictionaryV1} from "./IkhaaliDictionaryV1.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

/// @title khaaliDictionaryV1
/// @notice On-chain dictionary of words for khaaliNames
abstract contract khaaliDictionaryV1 is IkhaaliDictionaryV1 {

    /// @notice the length of each word in bytes
    uint256 private constant _WORD_LENGTH = 16;

    /// @notice we use SSTORE2 to store the data
    address private immutable _data;
    uint256 private immutable _count;


    constructor(address data, uint256 count) {
        _data = data;
        _count = count;
    }


    function wordCount() external view override returns (uint256) {
        return _count;
    }

    function wordAt(uint256 index) external view override returns (string memory) {
        require(index < _count, DictionaryIndexOutOfBounds(address(this), index, _count));

        // read bytes between index and index + 1
        bytes memory raw = SSTORE2.read(_data, index * _WORD_LENGTH, (index + 1) * _WORD_LENGTH);

        // return converted string
        return _bytesToString(raw);
    }


    /// @dev Convert the raw bytes to a string, trimming the padding bytes
    /// @notice 1 loop cheaper than 2 loops by 100-150 gas per call
    function _bytesToString(bytes memory raw) internal pure returns (string memory) {
        uint256 len;
        bytes memory word = new bytes(_WORD_LENGTH);
        for (len = 0; len < _WORD_LENGTH; len++) {
            if (raw[len] == 0) break;
            word[len] = raw[len];
        }
        assembly {
            mstore(word, len) // overwrite the length of the word
        }
        return string(word);
    }

}