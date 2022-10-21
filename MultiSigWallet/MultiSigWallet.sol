// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./Pausable.sol";

contract MultiSigWallet is Pausable {
    address[] private signers; //sahipleri tutan array.
    uint256 private requiredConfirmations; //önerinin onaylanması için gerekli onay sayısını yapıcıda belirledim.
    uint256 private nonce; //nonce değeri.
    mapping(uint256 => Tx) private queueTxs; //Transactionın kuyruktaki yeri
    mapping(uint256 => mapping(address => bool)) private txConfirmers; //transactionı onaylayanların listesi

    event NewProposal(address proposer, uint256 transactionId); //yeni öneri sunulması
    event Executed(address executor, uint256 transactionId, bool success); //önerinin kabulu ardından çalıştırılması
    event ExecutionFailure(uint256 indexed transactionId, bool success); //transaction fail olursa
    event Revocation(address indexed sender, uint256 indexed transactionId); // Tx revokelaninca.
    event Confirmation(address indexed sender, uint256 indexed transactionId); //Tx confirmleyince calisiyor.
    event Deposit(address indexed sender, uint256 value); //contrata ether gönderimi oldugunda.

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
        signers = _signers;
        requiredConfirmations = _requiredConfirmations;
    }

    //getter'lar.
    function getSigners() public view virtual returns (address[] memory) {
        return signers;
    }

    function getRequiredConfirmations() public view virtual returns (uint256) {
        return requiredConfirmations;
    }

    function getNonce() public view virtual returns (uint256) {
        return nonce;
    }

    function getQueueTxs(uint256 _number)
        public
        view
        virtual
        returns (Tx memory)
    {
        return queueTxs[_number];
    }

    function getTxConfirmers(uint256 _number, address _caller)
        public
        view
        virtual
        returns (bool)
    {
        return txConfirmers[_number][_caller];
    }

    //herhangi bir signer'ın yeni bir öneri yapması.
    function proposeTransaction(
        uint256 _deadline, //ileriye yönelik bi tarih.
        address _txAddress, //hedef adres
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
        emit Confirmation(msg.sender, _nonce);
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
        emit Revocation(msg.sender, _nonce);
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

        if (!txSuccess) {
            queueTxs[_nonce].executed = false;
            emit ExecutionFailure(_nonce, false);
        } //transaction başarısız olursa false ataması yapılır

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
        _pause(); //Pausable.sol method.
    }

    function unpause() external onlySigners whenPaused {
        _unpause(); //Pausable.sol method.
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

    receive() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    } //boş calldata geldiğinde çalışan, ödeme alan receive fonksiyonu

    fallback() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    } //payable fallback function
}

//["0x5B38Da6a701c568545dCfcB03FcB875f56beddC4","0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2","0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db"]
