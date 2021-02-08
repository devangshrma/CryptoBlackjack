// SPDX-License-Identifier: MIT
/*
*   @date: 2020-08-06
*   @authors: Devang, Sainath and Aditya
*   @version: 1.0
*   @platformInfo:  Remix IDE - compiler version 0.7.0
*   @about: An implementation of a game of BlackJack in Solidity using Remix IDE
*/
pragma solidity ^0.7.0;

contract Blackjack{

    struct gameInstance{
        bool rcvdWinAmt;
        uint256 betAmt;
        uint256 lastMoveTS;
        uint256 allotTime;
        uint8 playerScore;
        uint8 dealerScore;
        uint8 numOfCardsP;
        uint8 numOfCardsD;
        uint8[13] playerDeck;
        uint8[13] dealerDeck;
        uint8[13] sourceDeck;
        address payable playerAddr;
        uint256 insuranceBet;
        bool insuranceOpted;
    }

    mapping (address => uint) playerAddrIdMap; //player address to game id
    mapping (uint => gameInstance) gameIdMap; //game id to game instance
    address payable dealerAddr;

    uint256 private nonce;
    uint256 public totBetAmt;
    uint256 public minBet;
    uint256 public timeout;
    uint256 private gameId;
    uint8 private faceDownCard;

    modifier isDealer{
        require(dealerAddr == msg.sender, "Only dealer can call this function");
        _;
    }

    modifier isDealerBal(uint256 _totBetAmt){
        require(dealerAddr.balance >= 2*_totBetAmt, "Dealer does not have enough balance for this game (should be twice of the bet amount placed by player!!)"); //check whether to change balance to value
        _;
    }

    modifier isPlayer{
        require(msg.sender != dealerAddr, "Dealer should not call this function (Should only be called by player)");
        _;
    }

    modifier isCurrentlyPlaying{
        require(playerAddrIdMap[msg.sender] != 0, "This player is not the part of game yet or has already left!!");
        _;8,10
    }

    modifier isNewPlayer{
        require(playerAddrIdMap[msg.sender] == 0, "Player is already playing the game");
        _;
    }

    modifier ifPlayerWon{
        require(gameIdMap[gameId].rcvdWinAmt == false, "Player has already received the winning amount!");
        _;
    }

    modifier isBetDoubled{
        require(msg.value == gameIdMap[gameId].betAmt, "Double Down is not allowed since player's bet doesn't match with inital bet amount!!!");
        _;
    }

    event dealerInitBalance(address _dealerAddr, uint256 _dealerBal);
    constructor()
        payable{
            dealerAddr = msg.sender;
            minBet = 0.01 ether;
            timeout = 200;
            totBetAmt = 0;
            gameId = 0;

            emit dealerInitBalance(msg.sender, msg.value);
        }

    event playerInitBalance(address _playerAddr, uint256 _playerBal);
    function gameInit(address payable _playerAddr, uint256 _betAmt, uint256 _gameId)
        private{
            playerAddrIdMap[msg.sender] = _gameId;
            gameIdMap[_gameId].betAmt = _betAmt;
            gameIdMap[_gameId].playerAddr = _playerAddr;
            gameIdMap[_gameId].allotTime = 0;
            gameIdMap[_gameId].rcvdWinAmt = false;

            emit playerInitBalance(_playerAddr, _betAmt);
        }

    function deckInit(uint _gameId)
        private{
            for(uint8 i = 0; i < 13; i++){
                gameIdMap[_gameId].sourceDeck[i] = 4; //there are 4 suits in a deck
            }
        }

    function startGameNBet()
        public
        payable
        isDealerBal(msg.value+totBetAmt)
        isPlayer
        isNewPlayer
        returns(uint8[13] memory _playerDeck, uint8 _playerScore, uint8[13] memory _dealerDeck, uint8 _dealerScore, uint256 _totAmtWon){

            require(msg.value >= minBet, "The bet amount placed by player is less than minimum allowable bet amount of 0.01 ether");

            totBetAmt += msg.value; //global var
            gameId += 1;

            gameInit(msg.sender, msg.value, gameId);
            deckInit(gameId);

            uint8[3] memory _dealtCards;

            for(uint i = 0; i < 3; i++){
                _dealtCards[i] = _drawFromDeck(gameId);
            }

            gameIdMap[gameId].dealerDeck[0] = _dealtCards[0];
            gameIdMap[gameId].numOfCardsD += 1;
            gameIdMap[gameId].dealerScore += _dealtCards[0];

            gameIdMap[gameId].playerDeck[0] = _dealtCards[1];
            gameIdMap[gameId].playerDeck[1] = _dealtCards[2];
            gameIdMap[gameId].numOfCardsP += 2;
            gameIdMap[gameId].playerScore += (_dealtCards[1] + _dealtCards[2]);
            
            _checkForAceP(gameId);

            _playerDeck  = gameIdMap[gameId].playerDeck;
            _playerScore = uint8(gameIdMap[gameId].playerScore);
            _dealerDeck  = gameIdMap[gameId].dealerDeck;
            _dealerScore = uint8(gameIdMap[gameId].dealerScore);

            if (gameIdMap[gameId].playerScore == 21){
                address discardAddr;
                (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon, discardAddr) = stand();
            }else{
                gameIdMap[gameId].lastMoveTS = block.timestamp; //start the timer
            }
            
            return(_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon);
        }

    function hit()
        public
        isPlayer
        isCurrentlyPlaying
        returns(uint8[13] memory _playerDeck, uint8 _playerScore, uint8[13] memory _dealerDeck, uint8 _dealerScore, uint256 _totAmtWon){
            uint _gameId = playerAddrIdMap[msg.sender];                                 // Get player's game id

            if(block.timestamp > (gameIdMap[_gameId].lastMoveTS + timeout + gameIdMap[_gameId].allotTime)){// Player has to call hit() within max_wait period
                address discardAddr;
                (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon, discardAddr) = stand();
            }
            else{
                uint8 _newCard = _drawFromDeck(_gameId);
                gameIdMap[_gameId].playerDeck[gameIdMap[_gameId].numOfCardsP++] = _newCard;                  // it will add the card to stack of players
                gameIdMap[_gameId].playerScore += _newCard;

                _playerDeck  = gameIdMap[_gameId].playerDeck;
                _playerScore = uint8(gameIdMap[_gameId].playerScore);
                _dealerDeck  = gameIdMap[_gameId].dealerDeck;
                _dealerScore = uint8(gameIdMap[_gameId].dealerScore);

                if (gameIdMap[_gameId].playerScore > 21){                            // Busted!
                    dealerAddr.transfer(gameIdMap[_gameId].betAmt); //
                    (_playerDeck, _playerScore, _dealerDeck, _dealerScore) = resetGame(_gameId); //////////////
                }
                else{
                    gameIdMap[_gameId].lastMoveTS = block.timestamp;
                }
            }

            return (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon);
        }


    function _drawFromDeck(uint256 _gameId)
        private
        returns(uint8 _newCard){
            bool _gotCard = false;
            while(!_gotCard){
                uint256 _randVal = (_genRandom(_gameId) % 52) + 1;
                if(gameIdMap[_gameId].sourceDeck[_randVal % 13] > 0){                   
                    _newCard = uint8(_randVal % 13 + 1);
                    if(_newCard > 10){                                                 
                        _newCard = 10;
                    }
                    gameIdMap[_gameId].sourceDeck[_randVal % 13]--;
                    _gotCard = true;
                }
            }
        }
        
    event _gameDecision(string _dMsg);
        
    function stand()
        public
        isPlayer
        isCurrentlyPlaying
        returns(uint8[13] memory _playerDeck, uint8 _playerScore, uint8[13] memory _dealerDeck, uint8 _dealerScore, uint256 _totAmtWon, address _playerAddr){
            uint256 _gameId = playerAddrIdMap[msg.sender]; // retrieve gameId 
            (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon) = _leaveGame(_gameId);
            
            return (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon, msg.sender);
        }
        
    function doubledown()
        public
        payable
        isBetDoubled
        isDealerBal(msg.value+totBetAmt)
        isPlayer
        isCurrentlyPlaying
        returns(uint8[13] memory _playerDeck, uint8 _playerScore, uint8[13] memory _dealerDeck, uint8 _dealerScore, uint256 _totAmtWon){
            require(gameIdMap[gameId].numOfCardsP == 2, "Double down is not allowed after more than 2 cards are dealt!!");
            totBetAmt += msg.value;
            gameIdMap[gameId].betAmt += msg.value;
            
            if(block.timestamp > (gameIdMap[gameId].lastMoveTS + timeout + gameIdMap[gameId].allotTime)){// Player has to call hit() within max_wait period
                address discardAddr;
                (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon, discardAddr) = stand();
            }
            else{
                gameIdMap[gameId].lastMoveTS = block.timestamp;
                (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon) = hit();
                address discardAddr;
                (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon, discardAddr) = stand();
            }    
            
            return (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon);
        }
        
    function insurance()
        public
        payable
        isDealerBal(msg.value+totBetAmt)
        isPlayer
        isCurrentlyPlaying
        returns(uint8[13] memory _playerDeck, uint8 _playerScore, uint8[13] memory _dealerDeck, uint8 _dealerScore){
            require(gameIdMap[gameId].dealerDeck[0] == 1 && gameIdMap[gameId].numOfCardsD == 1, 
                            "Dealer's faceup card is not an Ace or dealer has more than one card");
            
            if(block.timestamp > (gameIdMap[gameId].lastMoveTS + timeout + gameIdMap[gameId].allotTime)){// Player has to call hit() within max_wait period
                address discardAddr; //ignore
                uint256 _totAmtWon; // ignore
                (_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon, discardAddr) = stand();
            }
            else{
                gameIdMap[gameId].lastMoveTS = block.timestamp;
                gameIdMap[gameId].insuranceBet = sideBet();
                gameIdMap[gameId].insuranceOpted = true;
            }
            
            return(_playerDeck, _playerScore, _dealerDeck, _dealerScore);
        }

    function sideBet()
        isPlayer
        view
        internal
        returns(uint256 _sideBet){
            require(msg.value*2 == gameIdMap[gameId].betAmt, "Sidebet should be half of original bet");
            _sideBet = msg.value;
        }

    function _genRandom(uint256 _gameId)
        internal
        returns(uint256 _randVal){
            bytes32 _hashval = keccak256(abi.encodePacked(block.timestamp, gameIdMap[_gameId].numOfCardsP, gameIdMap[_gameId].numOfCardsD, ++nonce));
            _randVal = uint256(_hashval);
        }
        
    function _checkForAceP(uint256 _gameId)
        private{
            for (uint8 i = 0; i < gameIdMap[_gameId].numOfCardsP; i++){
                // Ace = 1 or 11                                                                   // BEST POSSIBLE SCENARIO FOR ACE AFTER FOR CALCULATING TOTAL
                if (gameIdMap[_gameId].playerDeck[i] == 1 && gameIdMap[_gameId].playerScore + 10 <= 21)
                    gameIdMap[_gameId].playerScore += 10;
            }
        }

    function _leaveGame(uint _gameId)
        internal
        isCurrentlyPlaying
        ifPlayerWon
        returns(uint8[13] memory _playerDeck, uint8 _playerScore, uint8[13] memory _dealerDeck, uint8 _dealerScore, uint256 _totAmtWon){
            _totAmtWon = 0;
            _checkForAceP(_gameId);
            _checkDealerOutcome(_gameId);                                    // Dealer draws till dealer_score <= 17

            if ((gameIdMap[_gameId].playerScore > 21)){ // PLAYER: Busted or lost!!
                _totAmtWon = 0;
                emit _gameDecision("_leaveGame(): dealer got the balance!!!");
                dealerAddr.transfer(gameIdMap[_gameId].betAmt);
            }
            else if((gameIdMap[_gameId].dealerScore > gameIdMap[_gameId].playerScore) && gameIdMap[_gameId].dealerScore <= 21){
                _totAmtWon = 0;
                emit _gameDecision("_leaveGame(): dealer got the balance!!! else if()");
                dealerAddr.transfer(gameIdMap[_gameId].betAmt);
            }
            else{
                //_checkDealerOutcome(_gameId);                                    // Dealer draws till dealer_score <= 17

                if(gameIdMap[_gameId].insuranceOpted == true ){
                    if(gameIdMap[_gameId].dealerDeck[1] == 10){ //check faceDownCard whether it is 10 or a face card
                        _totAmtWon += (2*gameIdMap[_gameId].insuranceBet);
                    }
                    else if(gameIdMap[_gameId].dealerScore == 21 && gameIdMap[_gameId].playerScore == 21){
                        _totAmtWon += gameIdMap[_gameId].insuranceBet;
                    }
                }

                if(gameIdMap[_gameId].dealerScore > 21 || (gameIdMap[_gameId].playerScore > gameIdMap[_gameId].dealerScore)){ //dealer loses
                    gameIdMap[_gameId].rcvdWinAmt = true;
                    _totAmtWon += 2*gameIdMap[_gameId].betAmt;                     // ADD LOG - DEALER BUSTED ? OR PLAYER WON ?
                    gameIdMap[_gameId].playerAddr.transfer(_totAmtWon);               // Player wins 2*bet_amount
                }
                else if(gameIdMap[_gameId].playerScore == gameIdMap[_gameId].dealerScore){
                    gameIdMap[_gameId].rcvdWinAmt = true;                                            // TIE
                    _totAmtWon += gameIdMap[_gameId].betAmt;                               // Player gets back his bet_amount
                    gameIdMap[_gameId].playerAddr.transfer(_totAmtWon);
                }
            }
            
            (_playerDeck, _playerScore, _dealerDeck, _dealerScore) = resetGame(_gameId);
            
            return(_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon);
        }
        
    function _checkDealerOutcome(uint _gameId)
        private{
            uint8 _newCard;
            uint8 _numOfAce = 0;

            faceDownCard = _drawFromDeck(_gameId);                                   // face down code dealer
            gameIdMap[_gameId].dealerDeck[gameIdMap[_gameId].numOfCardsD] = faceDownCard;       // ADD FACEDOWN CARD AND NORMAL CARD OF DEALER
            gameIdMap[_gameId].numOfCardsD = 2;
            gameIdMap[_gameId].dealerScore += faceDownCard;
            
            if(faceDownCard == 1){
                _numOfAce++;
            }

            while (gameIdMap[_gameId].dealerScore <= 17){                            // Dealer draws till dealer_score <= 17
                _newCard = _drawFromDeck(_gameId);
                gameIdMap[_gameId].dealerDeck[gameIdMap[_gameId].numOfCardsD++] = _newCard;
                gameIdMap[_gameId].dealerScore += _newCard;
                if (_newCard == 1){ //if new_card is ace then increment ace counter by 1
                    _numOfAce++;
                }
            }

            if (gameIdMap[_gameId].dealerScore < 21){
                for (uint8 i = 0; i < _numOfAce; i++){
                    if (gameIdMap[_gameId].dealerScore + 10 <= 21){ //dealer is deciding what value he wants for ace
                        gameIdMap[_gameId].dealerScore += 10;
                    }
                }
            }
        }


    function ifPlayerTimeout(uint _gameId)
        external
        isDealer
        returns(uint8[13] memory _playerDeck, uint8 _playerScore, uint8[13] memory _dealerDeck, uint8 _dealerScore, uint256 _totAmtWon){
            if (block.timestamp > gameIdMap[_gameId].lastMoveTS + gameIdMap[_gameId].allotTime + timeout){
                _leaveGame(_gameId);
            }
            
            return(_playerDeck, _playerScore, _dealerDeck, _dealerScore, _totAmtWon);
        }

    function changeValues(uint _minBet, uint _timeout)
        external
        isDealer{
            minBet = _minBet;
            timeout = _timeout;
        }

    function reqMoreTime(uint _gameId, uint _requireTime)
        external
        isDealer{          // Dealer can add more time for a specific player
            gameIdMap[_gameId].allotTime = _requireTime; //additional time, not same as lastMoveTS
        }

    function resetGame(uint _gameId)
        private
        returns(uint8[13] memory _playerDeck, uint8 _playerScore, uint8[13] memory _dealerDeck, uint8 _dealerScore){
            _playerDeck = gameIdMap[_gameId].playerDeck;
            _playerScore = uint8(gameIdMap[_gameId].playerScore);
            _dealerDeck = gameIdMap[_gameId].dealerDeck;
            _dealerScore = uint8(gameIdMap[_gameId].dealerScore);
            
            if(_playerScore > _dealerScore && _playerScore <= 21){
                emit _gameDecision("resetGame(): Player has won the game!!!");
            }
            else if(_playerScore == _dealerScore){
                emit _gameDecision("resetGame(): Player has received the bet amount back!!!");
            }
            else{
                emit _gameDecision("resetGame(): Player got BUSTED or his score is less than dealer's!!!!");
            }
            
            totBetAmt -= gameIdMap[_gameId].betAmt;
            playerAddrIdMap[gameIdMap[_gameId].playerAddr] = 0;
            delete gameIdMap[_gameId];
            
            return(_playerDeck, _playerScore, _dealerDeck, _dealerScore);
        }

    function abortGame() 
        public
        isDealer{                                           // destroy contract
            selfdestruct(dealerAddr);
        }
}
