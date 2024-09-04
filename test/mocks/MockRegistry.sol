// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

contract MockRegistry {
    address _resolver;
    constructor(address resolver_) {
        _resolver = resolver_;
    }
    function resolver(bytes32 ) external view returns (address) {
        return _resolver;
    }
}