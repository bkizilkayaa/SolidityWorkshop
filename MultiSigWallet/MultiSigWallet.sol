// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./Pausable.sol";

contract MultiSigWallet is Pausable {
    address[] public signers; //sahipleri tutan array.
    uint256 public requiredConfirmations; //önerinin onaylanması için gerekli onay sayısını yapıcıda belirledim.
    uint256 public nonce; //nonce değeri.
    mapping(uint256 => Tx) public queueTxs; //Transactionın kuyruktaki yeri
    mapping(uint256 => mapping(address => bool)) public txConfirmers; //transactionı onaylayanların listesi

    event NewProposal(address proposer, uint256 id); //yeni öneri sunulması
    event Executed(address executor, uint256 id, bool success); //önerinin kabulu ardından çalıştırılması

    struct Tx {
        //transaction structı bu sekilde kurgulandı
        address proposer; //öneriyi yapan kişi
        uint256 confirmations; //aldığı onay sayisi
        bool executed; //çalıştırılıp çalıştırılmadığı
        uint256 deadline;
        address txAddress; //hedef adres
        uint256 value; //gönderilecek deger
        bytes txData; //gönderilecek data.
    }

    constructor(address[] memory _signers, uint256 _requiredConfirmations) {
        require(_signers.length > 0, "Not a valid signer.");
        require(isValid(_signers), "Duplicate addresses.");
        require(
            _requiredConfirmations <= _signers.length, //verilen parametrelerin mantıklı olup olmadığını kontrol ediyorum
            "Not enough signer."
        );
        super;
        signers = _signers;
        requiredConfirmations = _requiredConfirmations;
    }

    receive() external payable {} //boş calldata geldiğinde çalışan, ödeme alan receive fonksiyonu

    fallback() external payable {} //payable fallback function

    //herhangi bir signer'ın yeni bir öneri yapması.
    function proposeTransaction(
        uint256 _deadline, //ileriye yönelik bi tarih.
        address _txAddress, //transaction addressi
        uint256 _value, // ether değeri
        bytes calldata _txData //gönderilecek olan data
    ) external onlySigners checkTimestamp(_deadline) whenNotPaused {
        Tx memory _tx = Tx({
            proposer: msg.sender, //öneriyi yapan kişi msg.sender
            confirmations: 0, //henüz kimse tarafından confirm edilmedi
            executed: false,
            deadline: _deadline, //önerinin geçerli olacağı timestamp
            txAddress: _txAddress,
            value: _value, //ether değerleri vs burada tutuluyor
            txData: _txData //data gönderimi varsa
        });

        queueTxs[nonce] = _tx; //transaction kuyruğunun 0.nonce'una default bir Transaction ataması yapar.
        emit NewProposal(msg.sender, nonce); //ardından öneriyi yapanı ve önerinin kuyruktaki yerini loglar.
        nonce++; //nonce bir artarak kuyrukta bir sonraki transactionun yerleşmesi için bekler.
    }

    //signerlarin tx'lara onay vermelerini saglar.
    function approveTransaction(uint256 _nonce)
        external
        onlySigners
        whenNotPaused
    {
        require(_nonce < nonce, "Not an existing transaction");
        //geçerli bir nonce değeri lazım
        require(!txConfirmers[_nonce][msg.sender], "Already executed");
        //zaten onay sayısını toplayarak işleme koyulan bir öneriyi approvelatmıyorum
        require(queueTxs[_nonce].deadline > block.timestamp, "Out of time");
        //onaylanacak olan tx'ın deadlineı devam etmeli.

        queueTxs[_nonce].confirmations++; //confirm+1
        txConfirmers[_nonce][msg.sender] = true; //o öneriyi msg.sender onaylamış oldu
    }

    //signerlarin önceden onay verdiği tx'ları revokelamalarini saglar.
    function revokeTransaction(uint256 _nonce)
        external
        onlySigners
        whenNotPaused
    {
        require(_nonce < nonce, "Not an existing transaction");
        //geçerli bir nonce değeri lazım
        require(!txConfirmers[_nonce][msg.sender], "Already executed");
        //zaten onay sayısını toplayarak işleme koyulan bir öneriyi revokelayamıyoruz
        require(queueTxs[_nonce].deadline < block.timestamp, "Out of time");
        //revokelanacak olan tx'ın deadlineı devam etmeli.
        require(
            txConfirmers[_nonce][msg.sender],
            "You re not one of a confirmers"
        );
        //bir transactionı bir signer revoke edilebilmesi için önceden o tx i approvelamalı.
        queueTxs[_nonce].confirmations--; //confirm - 1
        txConfirmers[_nonce][msg.sender] = false; //o öneriyi msg.sender artık revokelamış oldu
    }

    function executeTx(uint256 _nonce)
        external
        onlySigners
        whenNotPaused
        returns (bool)
    {
        require(_nonce < nonce, "Not an existing transaction");
        //geçerli bir nonce değeri lazım
        require(!queueTxs[_nonce].executed, "Already executed");
        //zaten onay sayısını toplayarak işleme koyulan bir öneriyi revokelayamıyoruz
        require(queueTxs[_nonce].deadline > block.timestamp, "Out of time");
        //revokelanacak olan tx'ın deadlineı devam etmeli.

        require(
            queueTxs[_nonce].confirmations >= requiredConfirmations,
            "Not enough confirmers."
        );

        //transactiondaki value değerinin içerisindeki ether miktarı
        //kontratımdan küçük/eşit olmalı ki gönderim yapılabilsin.
        require(queueTxs[_nonce].value <= address(this).balance);

        //transaction executed
        queueTxs[_nonce].executed = true;

        (bool txSuccess, ) = (payable(queueTxs[_nonce].txAddress)).call{
            value: queueTxs[_nonce].value
        }(queueTxs[_nonce].txData);

        if (!txSuccess)
            //transaction başarısız olursa false ataması yapılır
            queueTxs[_nonce].executed = false; //burada hata/log fırlatmalıyım aslında.

        emit Executed(msg.sender, _nonce, txSuccess);
        return txSuccess;
    }

    //verilen arrayi kontrol edip bool döner.
    function isValid(address[] memory _signerArray)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < _signerArray.length - 1; i++) {
            for (uint256 j = i + 1; j < _signerArray.length; j++) {
                require(_signerArray[i] != address(0), "Invalid address"); //adresler boş olmamalı
                require(_signerArray[j] != address(0), "Invalid address");
                //ve adresler birbiriyle aynı olmamalı.
                require(
                    _signerArray[i] != _signerArray[j],
                    "Duplicate address."
                );
            }
        }
        return true;
    }

    function deleteTx(uint256 _nonce) external onlySigners whenNotPaused {
        require(_nonce < nonce, "Not an existing transaction");
        //geçerli bir nonce değeri lazım
        require(!txConfirmers[_nonce][msg.sender], "Already executed");
        //zaten onay sayısını toplayarak işleme koyulan bir öneriyi silemeyiz.
        require(
            queueTxs[_nonce].proposer == msg.sender,
            "Not a transaction owner."
        );
        //transactionı sadece signerlar içerisinden öneriyi yapan adres silebilir
        require(
            queueTxs[_nonce].confirmations < requiredConfirmations,
            "Already confirmed."
        );
        //istenilen onay sayısına ulaşmamış olmalı

        queueTxs[_nonce].executed = false;
        //executed false
    }

    function getBalance() public view onlySigners returns (uint256 _balance) {
        _balance = address(this).balance; //kontratın içerisindeki ether value return ediliyor..
    }

    function pause() external onlySigners whenNotPaused {
        //solidity tarafından kullanımı publicten internal'e değiştirildi.
        //bu sebeple -artık- super keywordü ile kullanıp kontratı kontrol edebiliyoruz.
        super._pause();
    }

    function unpause() external onlySigners whenPaused {
        super._unpause();
    }

    //signers array kontrolü
    modifier onlySigners() {
        bool isSigner = false;
        for (uint256 i; i < signers.length; i++) {
            if (signers[i] == msg.sender) {
                isSigner = true;
            }
        }
        require(isSigner, "You re not one of a signers");
        _;
    }

    //verilecek olan deadline, o anki block zamanından ileride olmalı.
    //mesela 2-3 hafta sonrasını işaret eden bir deadline olabilir.
    modifier checkTimestamp(uint256 _deadLine) {
        require(_deadLine > block.timestamp, "Out of time");
        _;
    }
}

contract A {
    uint256 public x;

    function increment() external {
        x++;
    }

    function getFnData() public pure returns (bytes memory) {
        return abi.encodeWithSignature("increment()");
    }
}

//["0x5B38Da6a701c568545dCfcB03FcB875f56beddC4","0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2","0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db"]
