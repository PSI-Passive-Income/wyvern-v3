/*

  << Exchange Core >>

*/

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "../lib/StaticCaller.sol";
import "../lib/ReentrancyGuarded.sol";
import "../lib/EIP1271.sol";
import "../registry/ProxyRegistryInterface.sol";
import "../registry/AuthenticatedProxy.sol";

/**
 * @title ExchangeCore
 * @author Wyvern Protocol Developers
 */
abstract contract ExchangeCore is ReentrancyGuarded, StaticCaller, EIP712Upgradeable {
    using Address for address;
    using ECDSAUpgradeable for bytes32;

    bytes4 public constant EIP_1271_MAGICVALUE = 0x1626ba7e;

    /* Struct definitions. */

    /* An order, convenience struct. */
    struct Order {
        /* Order registry address. */
        address registry;
        /* Order maker address. */
        address maker;
        /* Order static target. */
        address staticTarget;
        /* Order static selector. */
        bytes4 staticSelector;
        /* Order static extradata. */
        bytes staticExtradata;
        /* Order maximum fill factor. */
        uint256 maximumFill;
        /* Order listing timestamp. */
        uint256 listingTime;
        /* Order expiration timestamp - 0 for no expiry. */
        uint256 expirationTime;
        /* Order salt to prevent duplicate hashes. */
        uint256 salt;
    }

    /* A call, convenience struct. */
    struct Call {
        /* Target */
        address target;
        /* How to call */
        AuthenticatedProxy.HowToCall howToCall;
        /* Calldata */
        bytes data;
    }

    /* Constants */

    /* Order typehash for EIP 712 compatibility. */
    bytes32 constant ORDER_TYPEHASH =
        keccak256(
            "Order(address registry,address maker,address staticTarget,bytes4 staticSelector,bytes staticExtradata,uint256 maximumFill,uint256 listingTime,uint256 expirationTime,uint256 salt)"
        );

    /* Variables */

    /* Trusted proxy registry contracts. */
    mapping(address => bool) public registries;

    /* Order fill status, by maker address then by hash. */
    mapping(address => mapping(bytes32 => uint256)) public fills;

    /* Orders verified by on-chain approval.
       Alternative to ECDSA signatures so that smart contracts can place orders directly.
       By maker address, then by hash. */
    mapping(address => mapping(bytes32 => bool)) public approved;

    /* Events */

    event OrderApproved(
        bytes32 indexed hash,
        address registry,
        address indexed maker,
        address staticTarget,
        bytes4 staticSelector,
        bytes staticExtradata,
        uint256 maximumFill,
        uint256 listingTime,
        uint256 expirationTime,
        uint256 salt,
        bool orderbookInclusionDesired
    );
    event OrderFillChanged(
        bytes32 indexed hash,
        address indexed maker,
        uint256 newFill
    );
    event OrdersMatched(
        bytes32 firstHash,
        bytes32 secondHash,
        address indexed firstMaker,
        address indexed secondMaker,
        uint256 newFirstFill,
        uint256 newSecondFill,
        bytes32 indexed metadata
    );

    /* Functions */

    function hashOrder(Order memory order)
        internal
        pure
        returns (bytes32 hash)
    {
        /* Per EIP 712. */
        return
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.registry,
                    order.maker,
                    order.staticTarget,
                    order.staticSelector,
                    keccak256(order.staticExtradata),
                    order.maximumFill,
                    order.listingTime,
                    order.expirationTime,
                    order.salt
                )
            );
    }

    function exists(address what) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(what)
        }
        return size > 0;
    }

    function validateOrderParameters(Order memory order, bytes32 hash_)
        internal
        view
        returns (bool)
    {
        /* Order must be listed and not be expired. */
        if (
            order.listingTime > block.timestamp ||
            (order.expirationTime != 0 &&
                order.expirationTime <= block.timestamp)
        ) {
            return false;
        }

        /* Order must not have already been completely filled. */
        if (fills[order.maker][hash_] >= order.maximumFill) {
            return false;
        }

        /* Order static target must exist. */
        if (!exists(order.staticTarget)) {
            return false;
        }

        return true;
    }

    function validateOrderAuthorization(
        bytes32 hash_,
        address maker,
        bytes memory signature
    ) internal view returns (bool) {
        /* Memoized authentication. If order has already been partially filled, order must be authenticated. */
        if (fills[maker][hash_] > 0) {
            return true;
        }

        /* Order authentication. Order must be either: */

        /* (a): sent by maker */
        if (maker == msg.sender) {
            return true;
        }

        /* (b): previously approved */
        if (approved[maker][hash_]) {
            return true;
        }

        /* Calculate hash which must be signed. */
        bytes32 typedHash = _hashTypedDataV4(hash_);

        /* (c): Contract-only authentication: EIP/ERC 1271. */
        if (maker.isContract()) {
            if (
                ERC1271(maker).isValidSignature(typedHash, signature) ==
                EIP_1271_MAGICVALUE
            ) {
                return true;
            }
            return false;
        }

        /* (d): Account-only authentication: ECDSA-signed by maker. */
        return typedHash.recover(signature) == maker;
    }

    function encodeStaticCall(
        Order memory order,
        Call memory call,
        Order memory counterorder,
        Call memory countercall,
        address matcher,
        uint256 value,
        uint256 fill
    ) internal pure returns (bytes memory) {
        /* This array wrapping is necessary to preserve static call target function stack space. */
        address[7] memory addresses = [
            order.registry,
            order.maker,
            call.target,
            counterorder.registry,
            counterorder.maker,
            countercall.target,
            matcher
        ];
        AuthenticatedProxy.HowToCall[2] memory howToCalls = [
            call.howToCall,
            countercall.howToCall
        ];
        uint256[6] memory uints = [
            value,
            order.maximumFill,
            order.listingTime,
            order.expirationTime,
            counterorder.listingTime,
            fill
        ];
        return
            abi.encodeWithSelector(
                order.staticSelector,
                order.staticExtradata,
                addresses,
                howToCalls,
                uints,
                call.data,
                countercall.data
            );
    }

    function executeStaticCall(
        Order memory order,
        Call memory call,
        Order memory counterorder,
        Call memory countercall,
        address matcher,
        uint256 value,
        uint256 fill
    ) internal view returns (uint256) {
        return
            staticCallUint(
                order.staticTarget,
                encodeStaticCall(
                    order,
                    call,
                    counterorder,
                    countercall,
                    matcher,
                    value,
                    fill
                )
            );
    }

    function executeCall(
        ProxyRegistryInterface registry,
        address maker,
        Call memory call
    ) internal {
        /* Assert valid registry. */
        require(registries[address(registry)]);

        /* Assert target exists. */
        require(exists(call.target), "Call target does not exist");

        /* Retrieve delegate proxy contract. */
        OwnableDelegateProxy delegateProxy = registry.proxies(maker);

        /* Assert existence. */
        require(
            address(delegateProxy) != address(0),
            "Delegate proxy does not exist for maker"
        );

        /* Assert implementation. */
        require(
            delegateProxy.implementation() ==
                registry.delegateProxyImplementation(),
            "Incorrect delegate proxy implementation for maker"
        );

        /* Typecast. */
        AuthenticatedProxy proxy = AuthenticatedProxy(payable(delegateProxy));

        /* Execute order. */
        proxy.proxyAssert(
            call.target,
            call.howToCall,
            call.data
        );
    }

    function approveOrderHash(bytes32 hash_) internal {
        /* CHECKS */

        /* Assert order has not already been approved. */
        require(
            !approved[msg.sender][hash_],
            "Order has already been approved"
        );

        /* EFFECTS */

        /* Mark order as approved. */
        approved[msg.sender][hash_] = true;
    }

    function approveOrder(Order memory order, bool orderbookInclusionDesired)
        internal
    {
        /* CHECKS */

        /* Assert sender is authorized to approve order. */
        require(
            order.maker == msg.sender,
            "Sender is not the maker of the order and thus not authorized to approve it"
        );

        /* Calculate order hash. */
        bytes32 hash_ = hashOrder(order);

        /* Approve order hash. */
        approveOrderHash(hash_);

        /* Log approval event. */
        emit OrderApproved(
            hash_,
            order.registry,
            order.maker,
            order.staticTarget,
            order.staticSelector,
            order.staticExtradata,
            order.maximumFill,
            order.listingTime,
            order.expirationTime,
            order.salt,
            orderbookInclusionDesired
        );
    }

    function setOrderFill(bytes32 hash_, uint256 fill) internal {
        /* CHECKS */

        /* Assert fill is not already set. */
        require(
            fills[msg.sender][hash_] != fill,
            "Fill is already set to the desired value"
        );

        /* EFFECTS */

        /* Mark order as accordingly filled. */
        fills[msg.sender][hash_] = fill;

        /* Log order fill change event. */
        emit OrderFillChanged(hash_, msg.sender, fill);
    }

    function atomicMatch(
        Order memory firstOrder,
        Call memory firstCall,
        Order memory secondOrder,
        Call memory secondCall,
        bytes memory signatures,
        bytes32 metadata
    ) internal reentrancyGuard {
        /* CHECKS */

        /* Calculate first order hash. */
        bytes32 firstHash = hashOrder(firstOrder);

        /* Check first order validity. */
        require(
            validateOrderParameters(firstOrder, firstHash),
            "First order has invalid parameters"
        );

        /* Calculate second order hash. */
        bytes32 secondHash = hashOrder(secondOrder);

        /* Check second order validity. */
        require(
            validateOrderParameters(secondOrder, secondHash),
            "Second order has invalid parameters"
        );

        /* Prevent self-matching (possibly unnecessary, but safer). */
        require(firstHash != secondHash, "Self-matching orders is prohibited");

        /* Calculate signatures */
        (bytes memory firstSignature, bytes memory secondSignature) = abi
            .decode(signatures, (bytes, bytes));

        /* Check first order authorization. */
        require(
            validateOrderAuthorization(
                firstHash,
                firstOrder.maker,
                firstSignature
            ),
            "First order failed authorization"
        );

        /* Check second order authorization. */
        require(
            validateOrderAuthorization(
                secondHash,
                secondOrder.maker,
                secondSignature
            ),
            "Second order failed authorization"
        );

        /* INTERACTIONS */

        /* Transfer any msg.value.
           This is the first "asymmetric" part of order matching: if an order requires Ether, 
           it must be the first order. */
        if (msg.value > 0 && firstCall.target != address(this)) {
            payable(firstOrder.maker).call{value: msg.value};
        }

        /* Execute first call, assert success.
           This is the second "asymmetric" part of order matching: execution of the second order 
           can depend on state changes in the first order, but not vice-versa. */
        executeCall(
            ProxyRegistryInterface(firstOrder.registry),
            firstOrder.maker,
            firstCall
        );

        /* Execute second call, assert success. */
        executeCall(
            ProxyRegistryInterface(secondOrder.registry),
            secondOrder.maker,
            secondCall
        );

        /* Static calls must happen after the effectful calls so that they can check the resulting state. */
        executeStaticCalls(
            firstOrder,
            firstCall,
            firstHash,
            firstSignature,
            secondOrder,
            secondCall,
            secondHash,
            secondSignature,
            metadata
        );
    }

    function executeStaticCalls(
        Order memory firstOrder,
        Call memory firstCall,
        bytes32 firstHash,
        bytes memory firstSignature,
        Order memory secondOrder,
        Call memory secondCall,
        bytes32 secondHash,
        bytes memory secondSignature,
        bytes32 metadata
    ) internal {
        uint256 firstPreviousFill = fills[firstOrder.maker][firstHash];
        uint256 secondPreviousFill = fills[secondOrder.maker][secondHash];

        /* Execute first order static call, assert success, capture returned new fill. */
        uint256 firstFill = executeStaticCall(
            firstOrder,
            firstCall,
            secondOrder,
            secondCall,
            msg.sender,
            msg.value,
            firstPreviousFill
        );

        /* Execute second order static call, assert success, capture returned new fill. */
        uint256 secondFill = executeStaticCall(
            secondOrder,
            secondCall,
            firstOrder,
            firstCall,
            msg.sender,
            uint256(0),
            secondPreviousFill
        );

        /* EFFECTS */

        /* Update first order fill, if necessary. */
        if ((firstSignature.length == 64 || firstSignature.length == 65) && firstFill != firstPreviousFill) {
            fills[firstOrder.maker][firstHash] = firstFill;
        }

        /* Update second order fill, if necessary. */
        if ((secondSignature.length == 64 || secondSignature.length == 65) && secondFill != secondPreviousFill) {
            fills[secondOrder.maker][secondHash] = secondFill;
        }

        /* LOGS */

        /* Log match event. */
        emit OrdersMatched(
            firstHash,
            secondHash,
            firstOrder.maker,
            secondOrder.maker,
            firstFill,
            secondFill,
            metadata
        );
    }
}
