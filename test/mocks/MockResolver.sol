// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

contract MockResolver {
    string _name;
    address _addr;
    function setName(string memory name_) external {
        _name = name_;
    } 
    function name(bytes32) external view returns (string memory) {
        return _name;
    }
    function setAddr(address addr_) external {
        _addr = addr_;
    }
    function addr(bytes32) external view returns (address) {
        return _addr;
    }
}