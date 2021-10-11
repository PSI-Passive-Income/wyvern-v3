/*

  << Wyvern Exchange >>

*/

pragma solidity ^0.8.6;

import "./exchange/Exchange.sol";

/**
 * @title WyvernExchange
 * @author Wyvern Protocol Developers
 */
contract WyvernExchange is Exchange {
    string public constant name = "Wyvern Exchange";

    string public constant version = "3.1";

    string public constant codename = "Ancalagon";

    constructor(
        address[] memory registryAddrs,
        bytes memory customPersonalSignPrefix
    ) Exchange(name, version) {
        for (uint256 ind = 0; ind < registryAddrs.length; ind++) {
            registries[registryAddrs[ind]] = true;
        }
        if (customPersonalSignPrefix.length > 0) {
            personalSignPrefix = customPersonalSignPrefix;
        }
    }
}
