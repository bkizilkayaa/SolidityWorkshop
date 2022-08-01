// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract Lottery{
    address public owner;
    uint256 public totalParticipants;
    uint256 public expectedParticipantsCount;
    constructor(){
        owner=msg.sender;
        totalParticipants=0;
    }
    struct Participants{
        bool isHePay;
        address participantAddress;
    }
    mapping(uint256=>Participants) public participants;

    function joinLottery() checkEther checkTheCount checkForDoublePayment public payable{
            participants[totalParticipants].isHePay=true;
            participants[totalParticipants].participantAddress=msg.sender;
            totalParticipants++;
    }
    function setParticipantsCount(uint256 _value) onlyOwner public{
        expectedParticipantsCount=_value;
    }
    function generateRandom() isTicketsSold private view returns(uint){
        return uint256(keccak256(abi.encodePacked(block.timestamp,block.difficulty,  
        msg.sender))) % expectedParticipantsCount;
    }
    function setTheWinner() isTicketsSold onlyOwner public view returns(address _winner){
        uint256 luckyNumber=generateRandom();
        return participants[luckyNumber].participantAddress;
    }

    modifier checkEther(){
        require(msg.value>=0.01 ether,"Insufficient balance");
        _;
    }
    modifier checkTheCount(){
        require(totalParticipants<expectedParticipantsCount,"Lottery tickets sold out");
        _;
    }
    modifier isTicketsSold(){
        require(totalParticipants==expectedParticipantsCount,"We have more tickets to sold.");
        _;
    }
    modifier onlyOwner(){
        require(msg.sender==owner,"You are not authorized!");
        _;
    }
    modifier checkForDoublePayment(){
        for(uint256 i=0;i<totalParticipants;i++){
            if(participants[i].participantAddress==msg.sender)
            revert();
            else
              continue;
        }
         _;
    }


}
