// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./Factory.sol";
import "./MultiSigWallet.sol";

contract MultiSigWalletFactory is Factory {
    //verilen parametrelerle yeni bir multi-sig cüzdan oluşturur.
    //
    function create(address[] _signers, uint256 _requiredConfirmations)
        public
        returns (address wallet)
    {
        wallet = new MultiSigWallet(_signers, _requiredConfirmations);
        register(wallet);
    }
}
