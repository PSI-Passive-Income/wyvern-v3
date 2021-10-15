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
        address[] memory registryAddrs
    ) {
        for (uint256 ind = 0; ind < registryAddrs.length; ind++) {
            registries[registryAddrs[ind]] = true;
        }

        __EIP712_init_unchained(name, version);
    }
}
