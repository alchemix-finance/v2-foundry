// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0;

interface IRocketStorage {
    function getDeployedStatus() external view returns (bool);
    function getGuardian() external view returns(address);
    function setGuardian(address value) external;
    function confirmGuardian() external;

    function getAddress(bytes32 key) external view returns (address);
    function getUint(bytes32 key) external view returns (uint);
    function getString(bytes32 key) external view returns (string memory);
    function getBytes(bytes32 key) external view returns (bytes memory);
    function getBool(bytes32 key) external view returns (bool);
    function getInt(bytes32 key) external view returns (int);
    function getBytes32(bytes32 key) external view returns (bytes32);

    function setAddress(bytes32 key, address value) external;
    function setUint(bytes32 key, uint value) external;
    function setString(bytes32 key, string calldata value) external;
    function setBytes(bytes32 key, bytes calldata value) external;
    function setBool(bytes32 key, bool value) external;
    function setInt(bytes32 key, int value) external;
    function setBytes32(bytes32 key, bytes32 value) external;

    function deleteAddress(bytes32 key) external;
    function deleteUint(bytes32 key) external;
    function deleteString(bytes32 key) external;
    function deleteBytes(bytes32 key) external;
    function deleteBool(bytes32 key) external;
    function deleteInt(bytes32 key) external;
    function deleteBytes32(bytes32 key) external;

    function addUint(bytes32 key, uint256 amount) external;
    function subUint(bytes32 key, uint256 amount) external;

    function getNodeWithdrawalAddress(address nodeAddress) external view returns (address);
    function getNodePendingWithdrawalAddress(address nodeAddress) external view returns (address);
    function setWithdrawalAddress(address nodeAddress, address newWithdrawalAddress, bool confirm) external;
    function confirmWithdrawalAddress(address nodeAddress) external;
}