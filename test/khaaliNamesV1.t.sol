// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {khaaliNamesV1, Milestone, NameType} from "../src/khaaliNamesV1.sol";
import {IkhaaliDictionaryV1} from "../src/dictionary/IkhaaliDictionaryV1.sol";
import {ColorDictionaryV1} from "../src/dictionary/ColorDictionaryV1.sol";
import {AnimalDictionaryV1} from "../src/dictionary/AnimalDictionaryV1.sol";
import {AdjectiveDictionaryV1} from "../src/dictionary/AdjectiveDictionaryV1.sol";

contract khaaliNamesV1Test is Test {

    uint256 constant WORD_LENGTH = 16;

    uint256 constant COLOR_COUNT = 50;
    uint256 constant ANIMAL_COUNT = 350;
    uint256 constant ADJECTIVE_COUNT = 1200;

    khaaliNamesV1 public khaaliNames;
    IkhaaliDictionaryV1 public animalDict;
    IkhaaliDictionaryV1 public colorDict;
    IkhaaliDictionaryV1 public adjectiveDict;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");


    function setUp() public {
        address colorPointer = SSTORE2.write(_packWords("data/colors.txt", COLOR_COUNT));
        colorDict = new ColorDictionaryV1(colorPointer);

        address animalPointer = SSTORE2.write(_packWords("data/animals.txt", ANIMAL_COUNT));
        animalDict = new AnimalDictionaryV1(animalPointer);

        address adjectivePointer = SSTORE2.write(_packWords("data/adjectives.txt", ADJECTIVE_COUNT));
        adjectiveDict = new AdjectiveDictionaryV1(adjectivePointer);

        khaaliNames = new khaaliNamesV1(animalDict, colorDict, adjectiveDict);
    }

    // ------- Dictionary Tests ------- //

    function test_colorDict_wordCount() public view {
        assertEq(colorDict.wordCount(), COLOR_COUNT);
    }

    function test_animalDict_wordCount() public view {
        assertEq(animalDict.wordCount(), ANIMAL_COUNT);
    }

    function test_adjectiveDict_wordCount() public view {
        assertEq(adjectiveDict.wordCount(), ADJECTIVE_COUNT);
    }

    function test_colorDict_firstWord() public view {
        assertEq(colorDict.wordAt(0), "amber");
    }

    function test_animalDict_firstWord() public view {
        assertEq(animalDict.wordAt(0), "aardvark");
    }

    function test_adjectiveDict_firstWord() public view {
        assertEq(adjectiveDict.wordAt(0), "able");
    }

    function test_colorDict_lastWord() public view {
        assertEq(colorDict.wordAt(COLOR_COUNT - 1), "yellow");
    }

    function test_animalDict_lastWord() public view {
        assertEq(animalDict.wordAt(ANIMAL_COUNT - 1), "zebra");
    }

    function test_adjectiveDict_lastWord() public view {
        assertEq(adjectiveDict.wordAt(ADJECTIVE_COUNT - 1), "zygotic");
    }

    function test_revert_colorDict_outOfBounds() public {
        vm.expectRevert();
        colorDict.wordAt(COLOR_COUNT);
    }

    function test_revert_animalDict_outOfBounds() public {
        vm.expectRevert();
        animalDict.wordAt(ANIMAL_COUNT);
    }

    function test_revert_adjectiveDict_outOfBounds() public {
        vm.expectRevert();
        adjectiveDict.wordAt(ADJECTIVE_COUNT);
    }

    // ------- khaaliNames Tests ------- //

    // address check

    function test_dictAddresses() public view {
        assertEq(address(colorDict), address(khaaliNames.colorDict()));
        assertEq(address(animalDict), address(khaaliNames.animalDict()));
        assertEq(address(adjectiveDict), address(khaaliNames.adjectiveDict()));
    }

    // milestone tests

    function test_milestone_ANIMAL_30() public view {
        string memory name = khaaliNames.getRandomName(alice, Milestone.ANIMAL_30);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 1); // animal-n
        console.log("ANIMAL_30:", name); // manual check
    }

    function test_milestone_COLOR_ANIMAL_5() public view {
        string memory name = khaaliNames.getRandomName(alice, Milestone.COLOR_ANIMAL_5);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 2); // color-animal-n
        console.log("COLOR_ANIMAL_5:", name); // manual check
    }

    function test_milestone_ADJ_ANIMAL_2() public view {
        string memory name = khaaliNames.getRandomName(alice, Milestone.ADJ_ANIMAL_2);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 2); // adjective-animal-n
        console.log("ADJ_ANIMAL_2:", name); // manual check
    }

    function test_milestone_ADJ_COLOR_ANIMAL_3() public view {
        string memory name = khaaliNames.getRandomName(alice, Milestone.ADJ_COLOR_ANIMAL_3);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 3); // adjective-color-animal-n
        console.log("ADJ_COLOR_ANIMAL_3:", name); // manual check
    }

    function test_milestone_revert_NONE() public {
        vm.expectRevert();
        khaaliNames.getRandomName(alice, Milestone.NONE);
    }

    function test_milestone_revert_outOfBounds() public {
        uint8 invalid = uint8(type(Milestone).max) + 1;
        (bool success,) = address(khaaliNames).call(
            abi.encodeWithSignature("getRandomName(address,Milestone)", alice, invalid)
        );
        assertFalse(success);
    }

    // escape hatch tests

    function test_escapeHatch_ANIMAL() public view {
        string memory name = khaaliNames.getRandomName(alice, NameType.ANIMAL, 10);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 1); // animal-n
        console.log("ANIMAL:", name); // manual check
    }

    function test_escapeHatch_COLOR() public view {
        string memory name = khaaliNames.getRandomName(alice, NameType.COLOR, 10);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 1); // color-n
        console.log("COLOR:", name); // manual check
    }

    function test_escapeHatch_ADJECTIVE() public view {
        string memory name = khaaliNames.getRandomName(alice, NameType.ADJECTIVE, 10);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 1); // adjective-n
        console.log("ADJECTIVE:", name); // manual check
    }

    function test_escapeHatch_COLOR_ANIMAL() public view {
        string memory name = khaaliNames.getRandomName(alice, NameType.COLOR_ANIMAL, 10);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 2); // color-animal-n
        console.log("COLOR_ANIMAL:", name); // manual check
    }
    
    function test_escapeHatch_ADJECTIVE_ANIMAL() public view {
        string memory name = khaaliNames.getRandomName(alice, NameType.ADJECTIVE_ANIMAL, 10);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 2); // adjective-animal-n
        console.log("ADJECTIVE_ANIMAL:", name); // manual check
    }
    
    
    function test_escapeHatch_ADJECTIVE_COLOR_ANIMAL() public view  {
        string memory name = khaaliNames.getRandomName(alice, NameType.ADJECTIVE_COLOR_ANIMAL, 10);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 3); // adjective-color-animal-n
        console.log("ADJECTIVE_COLOR_ANIMAL:", name); // manual check
    }
    
    
    function test_escapeHatch_COLOR_ADJECTIVE_ANIMAL() public view {
        string memory name = khaaliNames.getRandomName(alice, NameType.COLOR_ADJECTIVE_ANIMAL, 10);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 3); // color-adjective-animal-n
        console.log("COLOR_ADJECTIVE_ANIMAL:", name); // manual check
    }

    function test_escapeHatch_revert_NONE() public {
        vm.expectRevert();
        khaaliNames.getRandomName(alice, NameType.NONE, 10);
    }

    function test_escapeHatch_revert_outOfBounds() public {
        uint8 invalid = uint8(type(NameType).max) + 1;
        (bool success,) = address(khaaliNames).call(
            abi.encodeWithSignature("getRandomName(address,NameType,uint8)", alice, invalid, 10)
        );
        assertFalse(success);
    }

    function test_escapeHatch_no_suffix() public view {
        string memory name = khaaliNames.getRandomName(alice, NameType.ANIMAL, 0);
        assertTrue(bytes(name).length > 0); // non-empty
        assertEq(_countHyphens(name), 0); // no hyphens
        console.log("NO_SUFFIX:", name); // manual check
    }
    
    // ------- randomness tests ------- //

    function test_same_seed_same_name() public view {
        string memory name1 = khaaliNames.getRandomName(alice, Milestone.ANIMAL_30);
        string memory name2 = khaaliNames.getRandomName(alice, Milestone.ANIMAL_30);
        assertEq(name1, name2);
    }

    function test_different_seed_different_name() public view {
        string memory name1 = khaaliNames.getRandomName(alice, Milestone.ANIMAL_30);
        string memory name2 = khaaliNames.getRandomName(bob, Milestone.ANIMAL_30);
        assertNotEq(name1, name2);
    }

    function test_different_block_different_name() public {
        string memory name1 = khaaliNames.getRandomName(alice, Milestone.ANIMAL_30);
        vm.warp(block.timestamp + 1);
        string memory name2 = khaaliNames.getRandomName(alice, Milestone.ANIMAL_30);
        assertNotEq(name1, name2);
    }

    // ------- Helpers ------- //

    function _countHyphens(string memory s) internal pure returns (uint256 count) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == 0x2D) count++; // hyphen
        }
    }

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

}