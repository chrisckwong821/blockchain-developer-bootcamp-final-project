pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IOBPMain.sol";

/// @title BettingOperator is the main contract that receives bet and gives payout.
/// @notice This contract should only be deployed through calling BettingOperatorDeployer
contract BettingOperator {
    
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    /// @dev This is a hash of the json of all the bettingItems using EIP 712 for typed structured data. Once deployed, the betters and referees depend on this hash to verify their source of truth
    uint256 public roothashOfbettingItems;
    address public OBPToken;
    address public OBPMain;

    address public owner;
    address public court;

    /// @dev defined an invited referee. Can only be set once
    address public referee;
    /// @dev OBP token locked for this Operator
    uint256 public refereeValueAtStake; 

    uint256 public feeToOperator;
    uint256 public feeToReferee;
    uint256 public feeToCourt;
    
    uint256 public unclaimedFeeToOperator;
    uint256 public unclaimedFeeToReferee;
    uint256 public unclaimedFeeToCourt;
    /// @dev accepted token for placing bet
    address public betToken;

    bool public canWithdraw = false;

    bool public verified = false;
    bool public setreferee = false;
    bool public setbettoken = false;
    
    mapping (uint256 => Pool) public bettingItems;

    struct Pool{
        //current total bet
        uint256 poolSize;
        //bettor => amount 
        mapping(address => uint256) bettors;
        // exp : PoolSize: (Pool1 : 1000), (Pool2: 1000)
        // then the poolPayout can look like (Pool1: 2000, Pool2: 0), (Pool1: 1500, Pool2: 500) etc
        uint256 payout;
        bool isClosed;
    }    
    // there would be a checking when Referee InjectResult so that the total payout cannot be bigger than the total bet 
    uint256 public totalReleasedPayout;
    // money that is claimed by bettor
    uint256 public totalClaimedPayout;
    uint256 public totalOperatorBet;
    uint256 public maxBetLimit;

    //snapshot upon confiscation
    uint256 public totalUnclaimedPayoutAfterConfiscation;
    
    uint private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, 'OBP: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor (address _OBPMain, address _OBPToken, address _owner, uint256 _roothashOfbettingItems, address _court, uint256 _feeToOperator, uint256 _feeToReferee, uint256 _feeToCourt) {
        OBPMain = _OBPMain;
        OBPToken = _OBPToken;
        owner = _owner;
        roothashOfbettingItems = _roothashOfbettingItems;
        court = _court;
        feeToOperator = _feeToOperator;
        feeToReferee = _feeToReferee;
        feeToCourt = _feeToCourt;
    }

    function setBetToken(address _bettoken) onlyOwner external {
        require(setbettoken == false, "setBetToken:: bettoken is already set") ;
        setbettoken = true;
        betToken = _bettoken;
    }
    function setReferee(address _referee) onlyOwner external {
        require(setreferee == false, "setReferee:: referee is already set") ;
        setreferee = true;
        referee = _referee;
    }
    function decodeResult(uint256 _encodedResult) public pure returns(uint112 item, uint112 payout, uint32 lastupdatedtime){
        item = uint112(_encodedResult>> 144);
        payout = uint112(_encodedResult >> 32);
        lastupdatedtime = uint32(_encodedResult);
    }

    modifier onlyReferee() {
        require(msg.sender == referee);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyCourt() {
        require(msg.sender == court);
        _;
    }
    function checkPoolPayout(uint256 _item) public view returns(uint256) {
        return bettingItems[_item].payout;
    }
    
    function checkPayoutByAddress(address _address, uint256 _item) public view returns(uint256) {
        return bettingItems[_item].bettors[_address] * bettingItems[_item].payout / bettingItems[_item].poolSize;
    }

    function withdrawOperatorFee(uint256 _amount, address _to)  external onlyOwner {
        require(unclaimedFeeToOperator - _amount >= 0, "withdrawOperatorFee:: THAT IS NO UNCLAIMED AMOUTN");
        unclaimedFeeToOperator -= _amount;
        (bool result) = IERC20(betToken).transfer(_to, _amount);
        require(result, "withdrawOperatorFee: TRANSFER_FAILED");
        // when operator withdraws fee, they are also responsible for settling the fee to the referee as well as the court.
        withdrawRefereeFee(unclaimedFeeToReferee);
        withdrawCourtFee(unclaimedFeeToCourt);

    }

    function withdrawRefereeFee(uint256 _amount) public {
        require(unclaimedFeeToReferee - _amount >= 0, "withdrawRefereeFee:: THAT IS NO UNCLAIMED AMOUTN");
        unclaimedFeeToReferee -= _amount;
        (bool result) = IERC20(betToken).transfer(referee, _amount);
        require(result, "withdrawRefereeFee: TRANSFER_FAILED");
    }

    function withdrawCourtFee(uint256 _amount) public {
        require(unclaimedFeeToCourt - _amount >= 0, "withdrawCourtFee:: THAT IS NO UNCLAIMED AMOUTN");
        unclaimedFeeToCourt -= _amount;
        (bool result) = IERC20(betToken).transfer(court, _amount);      
        require(result, "withdrawCourtFee: TRANSFER_FAILED");
    }




    function verify(uint256 _refereeValueAtStake, uint256 _maxBet, uint256 refereeIds) external onlyReferee {
        require(verified == false, "verify:: ALREADY VERIFIERD");
        require(IOBPMain(OBPMain).allReferees(refereeIds) == referee, "verify: refereeAddress not matching the required");
        verified = true;
        refereeValueAtStake = _refereeValueAtStake;
        maxBetLimit = _maxBet;
    }
    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::transferFrom: transferFrom failed'
        );
    }

    /// @notice directly place bet without going through Router,if the operator is approved for moving yr BetToken. Otherwise approve the BettingRouter for the betToken to achieve one-off aproval.
    function placeBet(uint item, uint amount, address bettor, bool isThroughRouter) lock external {
        require(bettingItems[item].isClosed == false, "the betting item is already closed"); 
        require(maxBetLimit - totalOperatorBet > amount, "placeBet:: the maxBet exceeds after taking this bet");
        if (!isThroughRouter) {
            _safeTransferFrom(betToken, bettor, address(this), amount);
        }
        // this line gets the exact amount that is deposited by the bettor
        //1. totalClaimedPayout - money that got drawn by winning bettor
        //2 .totalBet is allBet placed
        //3. unclaimedFee(s) are fee entitled to various parties, they just temporary sits at this address. 
        amount = IERC20(betToken).balanceOf(address(this)) 
        + totalClaimedPayout 
        - totalOperatorBet
        - unclaimedFeeToOperator - unclaimedFeeToReferee - unclaimedFeeToCourt;

        unclaimedFeeToOperator += (amount * feeToOperator) / 10**6;
        unclaimedFeeToReferee += (amount * feeToReferee) / 10**6;        
        unclaimedFeeToCourt += (amount * feeToCourt) / 10**6;

        uint256 Poolamount = amount * ( 10**6 - feeToReferee - feeToOperator - feeToCourt) / 10**6;
        bettingItems[item].bettors[bettor] = Poolamount;
        bettingItems[item].poolSize += Poolamount;
        totalOperatorBet += Poolamount;
    }
    /// @notice this is a function to withdraw normally, unless there is OBP compensation from confiscation, only 1 ERC20 transfer is involved.
    function withdraw(uint item, address _to) external {
        address bettor = msg.sender;
        require(bettingItems[item].isClosed, "the betting item is still open"); 
        require(bettingItems[item].payout > 0, "withdraw:: THERE is no Payout in this item");
        uint256 amount = checkPayoutByAddress(bettor, item);
        uint256 amountOBP = getAmountFromFailedReferee(item, bettor);
        totalClaimedPayout += amount;
        //remove the bet before transferring
        bettingItems[item].bettors[msg.sender] = 0;

        (bool result) = IERC20(betToken).transfer(_to, amount);
        require(result, "withdraw: TRANSFER_FAILED");
        if (amountOBP > 0 ) {
            // this number is non-zero only when OBP is confiscated from referee.
            // if you prefer getting the OBP instead of the payout, pls call withdrawFromFailedReferee(uint256 item, address _to);
            (bool resultToCourt) = IERC20(OBPToken).transfer(court, amountOBP);
            require(resultToCourt, "withdraw: TRANSFER_FAILED"); 
        }
    }

    function injectResult(uint256 item) external onlyReferee {
    (uint112 parsedItem, uint112 parsedPayout,) = decodeResult(item);
    // 0 can be a empty entry pushed from Referee
    if (parsedItem != 0 && bettingItems[item].isClosed == false) {
        // embed an update of payout in case a wrong value is pushed.
        // when an item is closed, bettor starts to claim and there is no way to correct any mistake
        uint256 oldPayout = bettingItems[parsedItem].payout;
        bettingItems[parsedItem].payout = parsedPayout;
        totalReleasedPayout = totalReleasedPayout + parsedPayout - oldPayout;
        }
    require(totalOperatorBet >= totalReleasedPayout ,"injectResult::the released payout is bigger than the total bet");
    }
    /// @dev inject any number of result to be pushed 
    function injectResultBatch(bytes calldata data) external onlyReferee {
        uint256 item;
        
        bytes memory tmpdata = data;
        for (uint256 i =0; i < tmpdata.length; i+=32) {
            assembly {
                item := mload(add(tmpdata, add(32, i)))
                }
        (uint112 parsedItem, uint112 parsedPayout, uint32 parsedPayoutLastUpdatedTime) = decodeResult(item);
        require(parsedItem >0 , "injectResultBatch:: 0 Ids is not allowed or non-existent");
            // 0 can be an empty entry pushed from Referee
            if (parsedItem != 0 && bettingItems[uint256(item)].isClosed == false) {
                // embed an update of payout in case a wrong value is pushed.
                // when an item is closed, bettor starts to claim and there is no way to correct any mistake
                uint256 oldPayout = bettingItems[parsedItem].payout;
                bettingItems[parsedItem].payout = parsedPayout;
                totalReleasedPayout = totalReleasedPayout + parsedPayout - oldPayout;
            }   
        }
        // assert at last injectedPayout is not more than the totalPayout, but not in the loop for efficient gas
        require(totalOperatorBet >= totalReleasedPayout ,"injectResultBatch::the released payout is bigger than the total bet");
        
    }
    
    function closeItem(uint256 item) external onlyReferee {
        bettingItems[item].isClosed = true;
    }

    /// @dev this is for closing item only, assuming data is parsed in itemId:payout::timestamp format, skipping every 32 bits that is payout data.
    function closeItemBatch(bytes calldata data) external onlyReferee {
        uint256 item;
        bytes memory tmpdata = data;
        
        for (uint i =0; i < tmpdata.length; i+=32) {
            assembly {
                item := mload(add(tmpdata, add(32, i)))
                }
            (uint112 parsedItem, , ) = decodeResult(item);
            bettingItems[parsedItem].isClosed = true;
        }
    }
    /// @dev this is to decide the portion of OBP each unclaimed bettor is eligible for. people who claim their money is not eligible
    function setTotalUnclaimedPayoutAfterConfiscation() external onlyCourt {
        
        totalUnclaimedPayoutAfterConfiscation = totalOperatorBet - totalClaimedPayout;
    }

    function getAmountFromFailedReferee(uint256 item, address bettor) view public returns(uint256) {
        if(totalUnclaimedPayoutAfterConfiscation == 0 ) {return 0;}
        return refereeValueAtStake * bettingItems[item].bettors[bettor] / totalUnclaimedPayoutAfterConfiscation;

    }
    function withdrawFromFailedReferee(uint256 item, address _to) external {
        //OBP is transferred from a failed refererr to this address.
        // once OBP is transferred in, those who hasnt claimed their payout, can decide if they want to claim OBP, or their payout.

        //all bettors WHO HAVENT CLAIMED THEIR PAYOUT get their shares based on their bet.
        // YOU EITHER GET YOUR PAYOUT(NO MATTER U WIN OR LOSS), OR THE OBP compensation.

        // if you get the OBP, your payout is donated to the court.
        // if you get the payout, your OBP is forfeited, and sent back to the court.
        address bettor = msg.sender;
        uint256 _amount = getAmountFromFailedReferee(item, bettor);
        require(_amount > 0, "withdrawFromFailedReferee:: THERE IS NO OBP FOR U");
        // originalBet to be sent to court
        uint256 originalPayout = checkPayoutByAddress(bettor, item);
        //set to 0 first to prevent re-entrance
        bettingItems[item].bettors[bettor] = 0;
        // send bet to court
        if (originalPayout > 0) {
            (bool resultToCourt) = IERC20(betToken).transfer(court, originalPayout);
            require(resultToCourt, "withdraw: TRANSFER_FAILED");
        }
        //take OBP
        (bool result) = IERC20(OBPToken).transfer(_to, _amount);
        require(result, "withdraw: TRANSFER_FAILED");
        

    }




}