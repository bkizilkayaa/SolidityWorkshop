//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;
 
abstract contract Pausable {

    event Paused(address account);   //paused by addr..
    event Unpaused(address account); //unpaused by addr..

    bool private _paused;

    //yapıcıda her kontrat durdurulmamış, çalışır kabul edilir.
    constructor() {
        _paused = false;
    }

    //kontratın durdurulup durdurulmadığı bilgisini tutan _paused değişkenini return'ler.
    function paused() public view virtual returns (bool) {
        return _paused;
    }

     //kontrat pause edilmişse istenen işlemleri revert eder.
    function _requireNotPaused() internal view virtual { 
        require(!paused(), "Pausable: paused");
    }

    //bir işlem gerçekleşmesi için kontratın önceden durdurulmuş olması gerekiyorsa kullanılır
    function _requirePaused() internal view virtual {  
        require(paused(), "Pausable: not paused");
    }

    //kontrat pause edilmemiş durumda ise pause'lar.
    function _pause() internal virtual whenNotPaused { 
        _paused = true;
        emit Paused(msg.sender);
    }

    //kontrat pause edilmiş durumda ise unpause'lar.
    function _unpause() internal virtual whenPaused { 
        _paused = false;
        emit Unpaused(msg.sender);
    }

    //modifierlar. inherit ettiğim yerde modifierlari kullanarak -
    //pause/unpause durumuna göre -
    //fonksiyonun çalışıp çalışmaması gerektiğini belirliyorum.
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }


}