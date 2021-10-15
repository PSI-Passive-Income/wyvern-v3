/*

  << Exchange >>

*/

pragma solidity ^0.8.6;

import "./ExchangeCore.sol";

/**
 * @title Exchange
 * @author Wyvern Protocol Developers
 */
abstract contract Exchange is ExchangeCore {
    /* external ABI-encodable method wrappers. */

    function hashOrder_(
        address registry,
        address maker,
        address staticTarget,
        bytes4 staticSelector,
        bytes calldata staticExtradata,
        uint256 maximumFill,
        uint256 listingTime,
        uint256 expirationTime,
        uint256 salt
    ) external pure returns (bytes32 hash) {
        return
            hashOrder(
                Order(
                    registry,
                    maker,
                    staticTarget,
                    staticSelector,
                    staticExtradata,
                    maximumFill,
                    listingTime,
                    expirationTime,
                    salt
                )
            );
    }

    function validateOrderParameters_(
        address registry,
        address maker,
        address staticTarget,
        bytes4 staticSelector,
        bytes calldata staticExtradata,
        uint256 maximumFill,
        uint256 listingTime,
        uint256 expirationTime,
        uint256 salt
    ) external view returns (bool) {
        Order memory order = Order(
            registry,
            maker,
            staticTarget,
            staticSelector,
            staticExtradata,
            maximumFill,
            listingTime,
            expirationTime,
            salt
        );
        return validateOrderParameters(order, hashOrder(order));
    }

    function validateOrderAuthorization_(
        bytes32 hash_,
        address maker,
        bytes calldata signature
    ) external view returns (bool) {
        return validateOrderAuthorization(hash_, maker, signature);
    }

    function approveOrderHash_(bytes32 hash_) external {
        return approveOrderHash(hash_);
    }

    function approveOrder_(
        address registry,
        address maker,
        address staticTarget,
        bytes4 staticSelector,
        bytes calldata staticExtradata,
        uint256 maximumFill,
        uint256 listingTime,
        uint256 expirationTime,
        uint256 salt,
        bool orderbookInclusionDesired
    ) external {
        return
            approveOrder(
                Order(
                    registry,
                    maker,
                    staticTarget,
                    staticSelector,
                    staticExtradata,
                    maximumFill,
                    listingTime,
                    expirationTime,
                    salt
                ),
                orderbookInclusionDesired
            );
    }

    function setOrderFill_(bytes32 hash_, uint256 fill) external {
        return setOrderFill(hash_, fill);
    }

    function atomicMatch_(
        uint256[16] memory uints,
        bytes4[2] memory staticSelectors,
        bytes memory firstExtradata,
        bytes memory firstCalldata,
        bytes memory secondExtradata,
        bytes memory secondCalldata,
        uint8[2] memory howToCalls,
        bytes32 metadata,
        bytes memory signatures
    ) public payable {
        return
            atomicMatch(
                Order(
                    address(uint160(uints[0])),
                    address(uint160(uints[1])),
                    address(uint160(uints[2])),
                    staticSelectors[0],
                    firstExtradata,
                    uints[3],
                    uints[4],
                    uints[5],
                    uints[6]
                ),
                Call(
                    address(uint160(uints[7])),
                    AuthenticatedProxy.HowToCall(howToCalls[0]),
                    firstCalldata
                ),
                Order(
                    address(uint160(uints[8])),
                    address(uint160(uints[9])),
                    address(uint160(uints[10])),
                    staticSelectors[1],
                    secondExtradata,
                    uints[11],
                    uints[12],
                    uints[13],
                    uints[14]
                ),
                Call(
                    address(uint160(uints[15])),
                    AuthenticatedProxy.HowToCall(howToCalls[1]),
                    secondCalldata
                ),
                signatures,
                metadata
            );
    }
}
