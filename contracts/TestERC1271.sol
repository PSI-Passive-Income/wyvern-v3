/*

  << TestERC1271 >>

*/

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./lib/EIP1271.sol";

contract TestERC1271 is ERC1271 {
    using ECDSA for bytes32;

    bytes4 internal constant SIGINVALID = 0x00000000;

    address internal owner;

    /**
     * Set a new owner (for testing)
     *
     * @param ownerAddr Address of owner
     */
    function setOwner(address ownerAddr) public {
        owner = ownerAddr;
    }

    /**
     * Check if a signature is valid
     *
     * @param _data Data signed over
     * @param _signature Encoded signature
     * @return magicValue Magic value if valid, zero-value otherwise
     */
    function isValidSignature(bytes calldata _data, bytes memory _signature)
        public
        view
        returns (bytes4 magicValue)
    {
        bytes32 hash = abi.decode(_data, (bytes32));
        return isValidSignature(hash, _signature);
    }

    /**
     * Check if a signature is valid
     *
     * @param _hash Data hash signed over
     * @param _signature Encoded signature
     * @return magicValue Magic value if valid, zero-value otherwise
     */
    function isValidSignature(bytes32 _hash, bytes memory _signature)
        public
        view
        override
        returns (bytes4 magicValue)
    {
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(
            _signature,
            (uint8, bytes32, bytes32)
        );
        return
            returnIsValidSignatureMagicNumber(
                owner == ecrecover(_hash, v, r, s)
            );
    }
}
