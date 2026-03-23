// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IkhaaliDictionaryV1
/// @notice Interface for on-chain word dictionaries used by khaaliNames
interface IkhaaliDictionaryV1 {

    error DictionaryIndexOutOfBounds(
        address dictionary,
        uint256 index,
        uint256 length
    );

    /// @notice Returns the total number of words in this dictionary
    function wordCount() external view returns (uint256);

    /// @notice Returns the word at the given index
    /// @param index The zero-based index of the word
    /// @return The word as a string
    function wordAt(uint256 index) external view returns (string memory);
}