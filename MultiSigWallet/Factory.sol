// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract Factory {
    //bir instance oluşturulduğunda loglaniyor.
    event ContractInstantiation(address sender, address instantiation);

    //instance oluşturup oluşturmadığı
    mapping(address => bool) public isInstantiation;

    //oluşturulan instancelarin listesi
    mapping(address => address[]) public instantiations;

    function getInstantiationCount(address creator)
        public
        view
        returns (uint256)
    {
        return instantiations[creator].length;
    }

    function register(address instantiation) internal {
        isInstantiation[instantiation] = true;
        instantiations[getSender()].push(instantiation);
        emit ContractInstantiation(getSender(), instantiation);
    }

    function getSender() internal view returns (address) {
        return msg.sender;
    }
}
