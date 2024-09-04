// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Registry} from "basenames/src/L2/Registry.sol";
import {IBasefriends} from "basefriends/src/IBasefriends.sol";
import {NameResolver} from "basenames/lib/ens-contracts/contracts/resolvers/profiles/NameResolver.sol";
import {AddrResolver} from "basenames/lib/ens-contracts/contracts/resolvers/profiles/AddrResolver.sol";
import {BASE_REVERSE_NODE, BASE_ETH_NODE} from "basenames/src/util/Constants.sol";
import {Sha3} from "basenames/src/lib/Sha3.sol";

contract BasefriendsHelper {
    
    Registry registry;
    IBasefriends basefriends;

    constructor(address registry_, address basefriends_) {
        registry = Registry(registry_);
        basefriends = IBasefriends(basefriends_);
    }

    function getFollowersFromAddress(address addr) public view returns (bool) {
        (bool revSuccess, string memory name) = getNameFromAddress(addr);
        if (!revSuccess) return false;
        (bool fwdSuccess, address fwdAddr) = getAddressFromName(name);
        if (!fwdSuccess) return false;
        if(fwdAddr != addr) return false;

        basefriends.getFollows(_getNodeFromName(name));
    }

    function getNameFromAddress(address addr) public view returns (bool, string memory) {
        bytes32 label = Sha3.hexAddress(addr);

        // @TODO we're using the base network reverse node on sepolia still
        bytes32 reverseNode = keccak256(abi.encodePacked(BASE_REVERSE_NODE, label)); 

        address resolver = registry.resolver(reverseNode);
        if(resolver == address(0)) return (false, "");

        string memory name = NameResolver(resolver).name(reverseNode);
        if(bytes(name).length == 0) return (false, "");

        return (true, name);
    }

    function getAddressFromName(string memory name) public view returns (bool, address) {
        bytes32 node = _getNodeFromName(name);
        
        address resolver = registry.resolver(node);
        if(resolver == address(0)) return (false, resolver);

        address addr = AddrResolver(resolver).addr(node);
        if(addr == address(0)) return (false, addr);

        return (true, addr);
    }

    function _getNodeFromName(string memory name) internal view returns (bytes32) {
        bytes32 label = keccak256(bytes(name));
        return keccak256(abi.encodePacked(_getRootNode(), label));
    }

    function _getRootNode() internal view returns (bytes32) {
        return block.chainid == 8453 ? 
            BASE_ETH_NODE : 
            bytes32(0x646204f07e7fcd394a508306bf1148a1e13d14287fa33839bf9ad63755f547c6); // basetest.eth
    }
}