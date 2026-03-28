// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {khaaliNamesV1} from "../src/khaaliNamesV1.sol";
import {IkhaaliDictionaryV1} from "../src/dictionary/IkhaaliDictionaryV1.sol";
import {ColorDictionaryV1} from "../src/dictionary/ColorDictionaryV1.sol";
import {AnimalDictionaryV1} from "../src/dictionary/AnimalDictionaryV1.sol";
import {AdjectiveDictionaryV1} from "../src/dictionary/AdjectiveDictionaryV1.sol";

contract DeployNamesV1 is Script {

    uint256 constant WORD_LENGTH = 16;
    
    uint256 constant COLOR_COUNT = 50;
    uint256 constant ANIMAL_COUNT = 350;
    uint256 constant ADJECTIVE_COUNT = 1200;

    uint256 immutable DEPLOYER_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function run() public {
        vm.startBroadcast(DEPLOYER_KEY);
        uint256 gasBefore = gasleft();

        (address colorPointer, uint256 colorDictSize) = _deployDictionary("data/colors.txt", COLOR_COUNT);
        IkhaaliDictionaryV1 colorDict = new ColorDictionaryV1(colorPointer);
        console.log("ColorDictionary:", address(colorDict));
        console.log("ColorDictionary size:", colorDictSize);

        (address animalPointer, uint256 animalDictSize) = _deployDictionary("data/animals.txt", ANIMAL_COUNT);
        IkhaaliDictionaryV1 animalDict = new AnimalDictionaryV1(animalPointer);
        console.log("AnimalDictionary:", address(animalDict));
        console.log("AnimalDictionary size:", animalDictSize);

        (address adjectivePointer, uint256 adjectiveDictSize) = _deployDictionary("data/adjectives.txt", ADJECTIVE_COUNT);
        IkhaaliDictionaryV1 adjectiveDict = new AdjectiveDictionaryV1(adjectivePointer);
        console.log("AdjectiveDictionary:", address(adjectiveDict));
        console.log("AdjectiveDictionary size:", adjectiveDictSize);

        khaaliNamesV1 khaaliNames = new khaaliNamesV1(
            IkhaaliDictionaryV1(animalDict), 
            IkhaaliDictionaryV1(colorDict), 
            IkhaaliDictionaryV1(adjectiveDict)
        );
        console.log("khaaliNamesV1:", address(khaaliNames));

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used:", gasUsed);
        vm.stopBroadcast();

        _writeDeploymentInfo(
            colorPointer, colorDictSize, address(colorDict),
            animalPointer, animalDictSize, address(animalDict),
            adjectivePointer, adjectiveDictSize, address(adjectiveDict),
            address(khaaliNames), gasUsed
        );
    }



    // ------- Helpers ------- //

    /// @dev Deploy a dictionary to SSTORE2
    function _deployDictionary(string memory filePath, uint256 count) 
        internal 
        returns (address pointer, uint256 size) 
    {
        bytes memory packed = _packWords(filePath, count);
        pointer = SSTORE2.write(_packWords(filePath, count));
        size = packed.length;
    }

    /// @dev Pack words into a bytes array for SSTORE2
    function _packWords(string memory filePath, uint256 count) 
        internal
        view
        returns (bytes memory)
    {

        string memory fileContent = vm.readFile(filePath);
        bytes memory raw = bytes(fileContent);
        bytes memory packed = new bytes(count * WORD_LENGTH);

        uint256 start = 0;
        uint256 index = 0;

        for (uint256 i = 0; i <= raw.length; i++) {
            if (i == raw.length || raw[i] == 0x0A) { // line feed
                uint256 len = i - start;
                // Strip trailing CR for CRLF compatibility
                if (len > 0 && raw[start + len - 1] == 0x0D) len--;
                if (len > 0) {
                    require(len <= WORD_LENGTH, "Word too long for bytes16");
                    for (uint256 j = 0; j < len; j++) {
                        packed[index * WORD_LENGTH + j] = raw[start + j];
                    }
                    index++;
                }
                start = i + 1;
            }
        }

        require(index == count, "Expected more words than found");
        return packed;
    }

    function _writeDeploymentInfo(
        address colorPointer, uint256 colorDictSize, address colorDictAddress,
        address animalPointer, uint256 animalDictSize, address animalDictAddress,
        address adjectivePointer, uint256 adjectiveDictSize, address adjectiveDictAddress,
        address khaaliNamesAddress, uint256 gasUsed
    ) internal {
        
        // build objects ---------

        string memory colorObj = "color";
        vm.serializeAddress(colorObj, "address", colorDictAddress);
        vm.serializeUint(colorObj, "count", COLOR_COUNT);
        vm.serializeAddress(colorObj, "data", colorPointer);
        string memory colorJson = vm.serializeUint(colorObj, "size", colorDictSize);


        string memory animalObj = "animal";
        vm.serializeAddress(animalObj, "address", animalDictAddress);
        vm.serializeUint(animalObj, "count", ANIMAL_COUNT);
        vm.serializeAddress(animalObj, "data", animalPointer);
        string memory animalJson = vm.serializeUint(animalObj, "size", animalDictSize);

        string memory adjObj = "adj";
        vm.serializeAddress(adjObj, "address", adjectiveDictAddress);
        vm.serializeUint(adjObj, "count", ADJECTIVE_COUNT);
        vm.serializeAddress(adjObj, "data", adjectivePointer);
        string memory adjJson = vm.serializeUint(adjObj, "size", adjectiveDictSize);

        // Nest under "dictionaries"
        string memory dictsObj = "dicts";
        vm.serializeString(dictsObj, "adjectives", adjJson);
        vm.serializeString(dictsObj, "animals", animalJson);
        string memory dictsJson = vm.serializeString(dictsObj, "colors", colorJson);

        // Build deployment content
        string memory info = "info";
        vm.serializeString(info, "dictionaries", dictsJson);
        vm.serializeAddress(info, "khaaliNamesV1", khaaliNamesAddress);
        vm.serializeUint(info, "gasUsed", gasUsed);
        string memory infoJson = vm.serializeUint(info, "timestamp", block.timestamp);

        // write to deployments.json ---------
        string memory root = "root";
        string memory json = vm.serializeString(root, vm.toString(block.chainid), infoJson);
        vm.writeJson(json, "deployments.json");
    }
}