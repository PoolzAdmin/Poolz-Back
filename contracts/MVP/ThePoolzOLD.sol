// SPDX-License-Identifier: MIT
pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract ThePoolz {
    constructor() public {
        Admin = msg.sender;
        Fee = 20; // *10000
        PozFee = 15; // *10000
        PozTimer = 1000; // *10000
        MinPoz = 80; // ^Token.decimals
        MinDuration = 0; //need to set
        poolsCount = 0; //Start with 0
        //investors data
        TotalInvestors = 0; // start with 0
    }

    event TransferOut(uint256 Amount, address To, address Token);
    event TransferOutETH(uint256 Amount, address To);
    event TransferIn(uint256 Amount, address From, address Token);
    event TransferInETH(uint256 Amount, address From);
    event NewPool(address token, uint256 id);
    event FinishPool(uint256 id);

    //event testing(uint256 amount); //will remove later

    function GetLastPoolId() public view returns (uint256) {
        return poolsCount;
    }

    function GetLastInvestorId() public view returns (uint256) {
        return TotalInvestors;
    }

    function WithdrawETHFee(address _to) public {
        require(msg.sender == Admin, "Only admin can take fee");
        _to.transfer(address(this).balance); // keeps only fee eth on contract //To Do need to take 16% to burn!!!
    }

    function transferOwnership(address _newOwner) public {
        require(msg.sender == Admin, "Only admin can do that");
        Admin = _newOwner;
    }

    //@dev not allow contract to receive funds
    function() public payable {
        revert();
    }

    address public Admin; //only admin can change the global settings
    //Global settings
    uint256 public Fee; //the fee for the pool
    uint256 public PozFee; // the fee for the first part of the pool
    uint256 public PozTimer; //the timer for the first part fo the pool
    //uint256 public PozDiscount; // The discout the first part of the pool got //*Moved inside the Pool, can select on create */
    //address FeeWallet; //keep in contract //the wallet getting the fee
    uint256 public MinPoz; //minimum ammount ofpoz to be part of the discount
    uint256 public MinDuration; //the minimum duration of a pool, in seconds
    enum PoolStatus {Created, Open, OutOfstock, Finished, Close} //the status of the pools
    //ERC20 public ERC20Interface; // for transfering ERC20 tokens // save the last token
    uint256 public poolsCount; // the ids of the pool
    struct Pool {
        address Token; //the address of the erc20 toke for sale
        address Creator; //the project owner
        uint256 FinishTime; //Until what time the pool is active
        uint256 Rate; //for eth Wei, in token, by the decemal. the cost of 1 token
        uint256 POZRate; //the rate for the until OpenForAll, if the same as Rate , OpenForAll = StartTime .
        address Maincoin; // on adress.zero = ETH
        uint256 StartAmount; //The total amount of the tokens for sale
        bool IsLocked; // true - the investors getting the tokens after the FinishTime. false - intant deal
        uint256 Lefttokens; // the ammount of tokens left for sale
        uint256 StartTime; // the time the pool open //TODO Maybe Delete this?
        uint256 OpenForAll; // The Time that all investors can invest
        uint256 UnlockedTokens; //for locked pools
        bool TookLeftOvers; //The Creator took the left overs after the pool finished
    }

    mapping(uint256 => Pool) public pools; //the id of the pool with the data
    mapping(address => uint256[]) public poolsMap; //the address and all of the pools id's
    mapping(address => bool) public ERC20MainCoins; //when approve new erc20 main coin - it will list here

    function AddERC20Maincoin(address _token) public {
        require(msg.sender == Admin);
        ERC20MainCoins[_token] = true;
    }

    function RemoveERC20Maincoin(address _token) public {
        require(msg.sender == Admin);
        ERC20MainCoins[_token] = false;
    }

    function IsERC20Maincoin(address _token) public view returns (bool) {
        return ERC20MainCoins[_token];
    }

    //create a new pool
    function CreatePool(
        address _Token, //token to sell address
        uint256 _FinishTime, //Until what time the pool will work
        uint256 _Rate, //the rate of the trade
        uint256 _POZRate, //the rate for POZ Holders
        uint256 _StartAmount, //Total amount of the tokens to sell in the pool
        bool _IsLocked, //False = DSP or True = TLP
        address _MainCoin // address(0x0) = ETH, address of main token
    ) external {
        require(IsERC20(_Token), "Need Valid ERC20 Token"); //check if _Token is ERC20
        require(now + MinDuration <= _FinishTime, "Need more then MinDuration"); // check if the time is OK
        require(
            TestAllownce(_Token, msg.sender, _StartAmount),
            "Must Approve the Transaction"
        );
        require(_MainCoin == address(0x0) || IsERC20Maincoin(_MainCoin));
        require(
            _Rate >= _POZRate,
            "POZ holders need to have better (or the same = off) price"
        );
        uint256 Openforall = (_Rate == _POZRate)
            ? block.timestamp
            : ((_FinishTime - block.timestamp) * PozTimer) /
                10000 +
                block.timestamp;
        //register the pool
        pools[poolsCount] = Pool(
            _Token,
            msg.sender,
            _FinishTime,
            _Rate,
            _POZRate,
            _MainCoin,
            _StartAmount,
            _IsLocked,
            _StartAmount,
            block.timestamp,
            Openforall,
            0,
            false
        );
        poolsMap[msg.sender].push(poolsCount);
        poolsCount++;
        //transfer the tokens
        ERC20(_Token).transferFrom(msg.sender, address(this), _StartAmount);
        emit TransferIn(_StartAmount, msg.sender, _Token);
        emit NewPool(_Token, poolsCount - 1);
    }

    function TestAllownce(
        address _token,
        address _owner,
        uint256 _amount
    ) public view returns (bool) {
        return ERC20(_token).allowance(_owner, address(this)) >= _amount;
    }

    // Basic check if this is a erc20 token
    function IsERC20(address _contractAddress) internal view returns (bool) {
        if (ERC20(_contractAddress).totalSupply() > 0) return true;
        return false;
    }

    //Give all the id's of the pools open by sender address
    function GetMyPoolsId() public view returns (uint256[]) {
        return poolsMap[msg.sender];
    }

    function WithdrawLeftOvers(uint256 _PoolId) external {
        require(
            pools[_PoolId].Creator == msg.sender || Admin == msg.sender,
            "Only the creator can Withdraw (or Admin)"
        ); //or admin
        require(pools[_PoolId].FinishTime <= now, "Can't withdrae yet");
        require(pools[_PoolId].Lefttokens > 0, "Nothnig to widraw");
        require(!pools[_PoolId].TookLeftOvers, "can't witdraw 2nd time");
        //pool is finished + got left overs + did not took them
        pools[_PoolId].TookLeftOvers = true;
        ERC20(pools[_PoolId].Token).transfer(
            pools[_PoolId].Creator,
            pools[_PoolId].Lefttokens
        );
        //check if owner, check if finished, check if got leftovers , transfer Tokens
    }

    //give the data of the pool, by id
    function GetPoolData(uint256 _id)
        public
        view
        returns (
            PoolStatus,
            address,
            uint256,
            uint256,
            address,
            uint256,
            uint256
        )
    {
        require(_id <= poolsCount, "Wrong Id");
        return (
            //check if sender POZ Invester?
            GetPoolStatus(_id),
            pools[_id].Token,
            pools[_id].Rate,
            pools[_id].POZRate,
            pools[_id].Maincoin, //incase of ETH will be address.zero
            pools[_id].StartAmount,
            pools[_id].Lefttokens
        );
    }

    function GetMorePoolData(uint256 _id)
        public
        view
        returns (
            bool,
            uint256,
            uint256,
            address
        )
    {
        return (
            pools[_id].IsLocked,
            pools[_id].FinishTime,
            pools[_id].OpenForAll,
            pools[_id].Creator
        );
    }

    //calculate the status of a pool - TODO
    function GetPoolStatus(uint256 _id) public view returns (PoolStatus) {
        require(_id <= poolsCount, "Wrong pool id");
        //Don't like the logic here - ToDo Boolean checks (truth table)
        if (now < pools[_id].OpenForAll && pools[_id].Lefttokens > 0) {
            //got tokens + only poz investors
            return PoolStatus.Created;
        }
        if (
            now >= pools[_id].OpenForAll &&
            pools[_id].Lefttokens > 0 &&
            now < pools[_id].FinishTime
        ) {
            //got tokens + all investors
            return PoolStatus.Open;
        }
        if (
            pools[_id].Lefttokens == 0 &&
            pools[_id].IsLocked &&
            now < pools[_id].FinishTime
        ) //no tokens on locked pool, got time
        {
            return PoolStatus.OutOfstock;
        }
        if (
            pools[_id].Lefttokens == 0 && !pools[_id].IsLocked
        ) //no tokens on direct pool
        {
            return PoolStatus.Close;
        }
        if (
            pools[_id].Lefttokens > 0 &&
            !pools[_id].IsLocked &&
            !pools[_id].TookLeftOvers
        ) {
            //Got left overs on direct pool
            return PoolStatus.Finished;
        }
        if (now >= pools[_id].FinishTime && !pools[_id].IsLocked) {
            // After finish time - not locked
            if (pools[_id].TookLeftOvers) return PoolStatus.Close;
            return PoolStatus.Finished;
        }
        if (now >= pools[_id].FinishTime && pools[_id].IsLocked) {
            // After finish time -  locked
            if (
                (pools[_id].TookLeftOvers || pools[_id].Lefttokens == 0) &&
                pools[_id].StartAmount - pools[_id].Lefttokens ==
                pools[_id].UnlockedTokens
            ) return PoolStatus.Close;
            return PoolStatus.Finished;
        }
    }

    address public POZ_Address = address(0x0);

    function IsPozInvestor(address _investor) public view returns (bool) {
        if (POZ_Address == address(0x0)) return true; // for test
        return (ERC20(POZ_Address).balanceOf(_investor) >= MinPoz);
    }
    //@dev Send in wei
    function InvestETH(uint256 _PoolId) external payable {
        require(_PoolId < poolsCount, "Wrong pool id");
        require(pools[_PoolId].Maincoin == address(0x0), "Pool is not for ETH");
        require(msg.value > 0, "send ETH to invest");
        require(msg.value > 10000, "send more ETH to invest");
        //check if Poz investor;
        emit TransferInETH(msg.value, msg.sender);
        Investors[TotalInvestors] = Investor(
            _PoolId,
            msg.sender,
            msg.value,
            IsPozInvestor(msg.sender),
            0,
            block.timestamp
        );
        InvestorsMap[msg.sender].push(TotalInvestors);
        TotalInvestors++;
        if (
            GetPoolStatus(_PoolId) == PoolStatus.Created &&
            IsPozInvestor(msg.sender) &&
            WithDiscount <= pools[_PoolId].Lefttokens //Got The Tokens
        ) {
            uint256 WithDiscount = msg.value / pools[_PoolId].POZRate;
            //Only for Poz Investor, better price
            pools[_PoolId].Lefttokens -= WithDiscount;
            if (pools[_PoolId].IsLocked) {
                Investors[TotalInvestors - 1].TokensOwn += WithDiscount;
            } else {
                // not locked, will transfer the toke
                TransferToken(pools[_PoolId].Token, msg.sender, WithDiscount);
            }
            uint256 EthMinusFee = (msg.value / 10000) * (10000 - PozFee);
            TransferETH(
                pools[_PoolId].Creator,
                EthMinusFee
            ); // send money to project owner - the fee stays on contract
            if (pools[_PoolId].Lefttokens == 0) emit FinishPool(_PoolId);
            return;
        }
        if (
            GetPoolStatus(_PoolId) == PoolStatus.Open &&
            TokensAmount <= pools[_PoolId].Lefttokens //Got The Tokens
        ) {
            uint256 TokensAmount = msg.value / pools[_PoolId].Rate;
            //all can invest, no discout price
            pools[_PoolId].Lefttokens -= TokensAmount;
            if (pools[_PoolId].IsLocked) {
                Investors[TotalInvestors - 1].TokensOwn += TokensAmount;
            } else {
                // not locked, will transfer the tokens
                TransferToken(pools[_PoolId].Token, msg.sender, TokensAmount);
            }
            TransferETH(
                pools[_PoolId].Creator,
                (msg.value / 10000) * (10000 - Fee)
            ); // send money to project owner - the fee stays on contract
            if (pools[_PoolId].Lefttokens == 0) emit FinishPool(_PoolId);
            return;
        }
        //can't invest OutOfstock,Finished,Close // TODO - make msg
        revert("Investment not complited");
    }
    function TransferToken(
        address _Token,
        address _Reciver,
        uint256 _ammount
    ) internal {
        emit TransferOut(_ammount, _Reciver, _Token);
        ERC20(_Token).transfer(_Reciver, _ammount);
    }

    function TransferETH(address _Reciver, uint256 _ammount) internal {
        emit TransferOutETH(_ammount, _Reciver);
        _Reciver.transfer(_ammount);
    }

    function InvestERC20(uint256 _PoolId,uint _Amount) external payable {
        require(_PoolId < poolsCount, "Wrong pool id");
        require(pools[_PoolId].Maincoin != address(0x0), "Pool is for ETH, use InvetETH");
        require(ERC20(pools[_PoolId].Maincoin).allowance(msg.sender,address(this)) >= _Amount, "Tokens not aproved");
        require(_Amount > 10000, "Need invest more then 10000");
        ERC20(pools[_PoolId].Maincoin).transferFrom(msg.sender,address(this),_Amount);
        emit TransferIn(_Amount, msg.sender, pools[_PoolId].Token);
        Investors[TotalInvestors] = Investor(
            _PoolId,
            msg.sender,
            _Amount,
            IsPozInvestor(msg.sender),
            0,
            block.timestamp
        );
        InvestorsMap[msg.sender].push(TotalInvestors);
        TotalInvestors++;
        if (
            GetPoolStatus(_PoolId) == PoolStatus.Created &&
            IsPozInvestor(msg.sender) &&        //check if Poz investor;
            WithDiscount <= pools[_PoolId].Lefttokens //Got The Tokens
        ) {
            uint256 WithDiscount = _Amount / pools[_PoolId].POZRate;
            //Only for Poz Investor, better price
            pools[_PoolId].Lefttokens -= WithDiscount;
            if (pools[_PoolId].IsLocked) {
                Investors[TotalInvestors - 1].TokensOwn += WithDiscount;
            } else {
                // not locked, will transfer the toke
                TransferToken(pools[_PoolId].Token, msg.sender, WithDiscount);
            }
            uint256 EthMinusFee = (_Amount / 10000) * (10000 - PozFee);
            TransferToken(
                pools[_PoolId].Maincoin,
                pools[_PoolId].Creator,
                EthMinusFee
            ); // send money to project owner - the fee stays on contract
            if (pools[_PoolId].Lefttokens == 0) emit FinishPool(_PoolId);
            return;
        }
        if (
            GetPoolStatus(_PoolId) == PoolStatus.Open &&
            TokensAmount <= pools[_PoolId].Lefttokens //Got The Tokens
        ) {
            uint256 TokensAmount = _Amount / pools[_PoolId].Rate;
            //all can invest, no discout price
            pools[_PoolId].Lefttokens -= TokensAmount;
            if (pools[_PoolId].IsLocked) {
                Investors[TotalInvestors - 1].TokensOwn += TokensAmount;
            } else {
                // not locked, will transfer the tokens
                TransferToken(pools[_PoolId].Token, msg.sender, TokensAmount);             
            }
            TransferToken(pools[_PoolId].Maincoin,pools[_PoolId].Creator,(_Amount / 10000) * (10000 - Fee)); // send money to project owner - the fee stays on contract
            if (pools[_PoolId].Lefttokens == 0) emit FinishPool(_PoolId);
            return;
        }
        //can't invest OutOfstock,Finished,Close // TODO - make msg
        revert("Investment not complited");
    }

    function WithdrawInvestment(uint256 _id) public {
        require(
            msg.sender == Investors[_id].InvestorAddress || msg.sender == Admin,
            "Only Investor can Withdraw (Or Admin)"
        );
        require(_id < TotalInvestors, "Wrong id");
        require(Investors[_id].TokensOwn > 0, "No tokens to Withdraw");
        emit TransferOut(
            Investors[_id].TokensOwn,
            Investors[_id].InvestorAddress,
            pools[Investors[_id].Poolid].Token
        );
        ERC20(pools[Investors[_id].Poolid].Token).transfer(
            Investors[_id].InvestorAddress,
            Investors[_id].TokensOwn
        );
        Investors[_id].TokensOwn = 0;
    }

    //Give all the id's of the investment  by sender address
    function GetMyInvestmentIds() public view returns (uint256[]) {
        return InvestorsMap[msg.sender];
    }

    //Investorsr Data
    uint256 TotalInvestors;
    mapping(uint256 => Investor) Investors;
    mapping(address => uint256[]) InvestorsMap;
    struct Investor {
        uint256 Poolid; //the id of the pool, he got the rate info and the token, check if looked pool
        address InvestorAddress; //
        uint256 MainCoin; //the amount of the main coin invested (eth/dai), calc with rate
        bool IsPozInvestor; //If the blance of the address got > MinPoz, can get discout if got early
        uint256 TokensOwn; //the amount of Tokens the investor needto get from the contract
        uint256 InvestTime; //the time that investment made
    }
} //end of ThePoolz