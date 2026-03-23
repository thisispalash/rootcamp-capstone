// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IkhaaliDictionaryV1} from "./dictionary/IkhaaliDictionaryV1.sol";
import {IkhaaliNamesV1, NameType, Milestone} from "./IkhaaliNamesV1.sol";

/// @title khaaliNamesV1
/// @notice On-chain random name generator. Generates human-readable names from
///         combinations of animals, colors, and adjectives with a numeric suffix.
/// @dev Deployed once with immutable dictionary references. Anyone can call it.
contract khaaliNamesV1 is IkhaaliNamesV1 {

    IkhaaliDictionaryV1 public immutable animalDict;
    IkhaaliDictionaryV1 public immutable colorDict;
    IkhaaliDictionaryV1 public immutable adjectiveDict;

    constructor(
        IkhaaliDictionaryV1 _animalDict,
        IkhaaliDictionaryV1 _colorDict,
        IkhaaliDictionaryV1 _adjectiveDict
    ) {
        animalDict = _animalDict;
        colorDict = _colorDict;
        adjectiveDict = _adjectiveDict;
    }


    function getRandomName(address recipient, Milestone milestone) 
        external 
        view 
        override
        returns (string memory) 
    {
        return _nameFromMilestone(recipient, milestone);
    }

    function getRandomName(address recipient, NameType nameType, uint8 n) 
        external 
        view 
        override
        returns (string memory) 
    {
        if (nameType == NameType.NONE) revert InvalidNameType();
        return _generate(recipient, nameType, n);
    }


    // ------------------------ Internal logic ------------------------

    /// @dev Maps a Milestone to its (NameType, n) pair and generates.
    function _nameFromMilestone(address recipient, Milestone milestone) 
        internal 
        view 
        returns (string memory) 
    {
        if (milestone == Milestone.ANIMAL_30) {
            return _generate(recipient, NameType.ANIMAL, 30);
        } else if (milestone == Milestone.COLOR_ANIMAL_5) {
            return _generate(recipient, NameType.COLOR_ANIMAL, 5);
        } else if (milestone == Milestone.ADJ_ANIMAL_2) {
            return _generate(recipient, NameType.ADJECTIVE_ANIMAL, 2);
        } else if (milestone == Milestone.ADJ_COLOR_ANIMAL_3) {
            return _generate(recipient, NameType.ADJECTIVE_COLOR_ANIMAL, 3);
        }
        revert UnsupportedMilestone();
    }

    /// @dev Core generation logic. Picks words from dictionaries based on NameType,
    ///      concatenates them with hyphens, and appends a numeric suffix in [1, n].
    function _generate(address recipient, NameType nameType, uint8 n) 
        internal 
        view 
        returns (string memory) 
    {
        
        // Seed from recipient + some on-chain entropy
        /// @dev can also use RSK Bridge precompile ~ 0x0000000000000000000000000000000001000006
        ///      to get getBtcBlockchainBestBlockHeader()
        uint256 seed = uint256(keccak256(abi.encodePacked(recipient, block.difficulty, block.timestamp)));

        // Build the name parts
        bytes memory name;

        if (nameType == NameType.ANIMAL) {
            name = abi.encodePacked(_pickWord(animalDict, seed, 0));
        } else if (nameType == NameType.COLOR) {
            name = abi.encodePacked(_pickWord(colorDict, seed, 0));
        } else if (nameType == NameType.ADJECTIVE) {
            name = abi.encodePacked(_pickWord(adjectiveDict, seed, 0));
        } else if (nameType == NameType.COLOR_ANIMAL) {
            name = abi.encodePacked(
                _pickWord(colorDict, seed, 0),
                "-",
                _pickWord(animalDict, seed, 1)
            );
        } else if (nameType == NameType.ADJECTIVE_ANIMAL) {
            name = abi.encodePacked(
                _pickWord(adjectiveDict, seed, 0),
                "-",
                _pickWord(animalDict, seed, 1)
            );
        } else if (nameType == NameType.COLOR_ADJECTIVE_ANIMAL) {
            name = abi.encodePacked(
                _pickWord(colorDict, seed, 0),
                "-",
                _pickWord(adjectiveDict, seed, 1),
                "-",
                _pickWord(animalDict, seed, 2)
            );
        } else if (nameType == NameType.ADJECTIVE_COLOR_ANIMAL) {
            name = abi.encodePacked(
                _pickWord(adjectiveDict, seed, 0),
                "-",
                _pickWord(colorDict, seed, 1),
                "-",
                _pickWord(animalDict, seed, 2)
            );
        } else {
            revert InvalidNameType();
        }

        if (n == 0) return string(name);

        // Append numeric suffix: -n where n is in [1, n]
        uint256 suffix = (uint256(keccak256(abi.encodePacked(seed, "suffix"))) % n) + 1;

        return string(abi.encodePacked(name, "-", _uint2str(suffix)));
    }

    /// @dev Pick a word from a dictionary using a seed and a salt to vary selection
    ///      across multiple word slots in the same name.
    function _pickWord(IkhaaliDictionaryV1 dict, uint256 seed, uint8 salt) 
        internal 
        view 
        returns (string memory) 
    {
        uint256 count = dict.wordCount();
        uint256 index = uint256(keccak256(abi.encodePacked(seed, salt))) % count;
        return dict.wordAt(index);
    }

    /// @dev Convert a uint256 to its decimal string representation.
    function _uint2str(uint256 value) 
        internal 
        pure 
        returns (string memory) 
    {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(0x30 + (value % 10))); // 0x30 is the ASCII code for '0'
            value /= 10;
        }

        return string(buffer);
    }
}