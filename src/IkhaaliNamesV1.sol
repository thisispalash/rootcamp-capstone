// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Opinion → Size → Age → Shape → Color → Origin → Material → Purpose → Noun

/// @notice The type of name to generate. Determines which dictionaries are used
///         and in what order the words appear.
enum NameType {
    NONE,                    // 0 - no-op, reverts
    ANIMAL,                  // 1 - 350 unique names
    COLOR,                   // 2 - 50 unique names
    ADJECTIVE,               // 3 - 1200 unique names
    COLOR_ANIMAL,            // 4 - 50 * 350 = 17_500 unique names
    ADJECTIVE_ANIMAL,        // 5 - 1200 * 350 = 420_000 unique names
    ADJECTIVE_COLOR_ANIMAL,  // 6 - 1200 * 50 * 350 = 21_000_000 unique names
    COLOR_ADJECTIVE_ANIMAL   // 7 (non-native) - 21_000_000 unique names
}

/// @notice Opinionated milestone presets that map to (NameType, n) pairs.
///         As a project grows, it can move to higher milestones for more unique names.
enum Milestone {
    NONE,                // 0 - no-op, reverts
    ANIMAL_30,           // n in [1,30] :: first ~10k users
    COLOR_ANIMAL_5,      // n in [1,5]  :: next ~90k users
    ADJ_ANIMAL_2,        // n in [1,2]  :: next ~900k users
    ADJ_COLOR_ANIMAL_3   // n in [1,3]  :: next ~49m users
}

/// @title IkhaaliNamesV1
/// @notice Interface for on-chain random name generator
interface IkhaaliNamesV1 {

    error InvalidNameType();
    error UnsupportedMilestone();

    /// @notice Generate a name using an opinionated milestone preset.
    /// @param recipient The address used as a seed for randomness.
    /// @param milestone The milestone preset to use.
    /// @return The generated name string.
    function getRandomName(address recipient, Milestone milestone) external view returns (string memory);
    
    /// @notice Escape hatch — caller picks the name type and numeric suffix range.
    /// @param recipient The address used as a seed for randomness.
    /// @param nameType  The name composition to use.
    /// @param n         The upper bound of the numeric suffix (1-based, inclusive).
    /// @return The generated name string.
    function getRandomName(address recipient, NameType nameType, uint8 n) external view returns (string memory);
}