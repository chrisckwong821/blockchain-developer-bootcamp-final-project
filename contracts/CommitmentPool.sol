pragma solidity >= 0.8.0;

import './interfaces/ICommitmentPool.sol';
import './libraries/TransferHelper.sol';
contract CommitmentPool
{
    Commitment[] public commitments; // initiator => counterparty => Commitments[];

    enum CommitmentType {Pure, Locking, Option}

    struct Commitment { 
        address initiator; 
        address counterparty; 
        uint256 amount; 
        address token;  
        uint256 expiry; 
        Trade trade;
        CommitmentType commitment_type; 
        bool active; 
        bool fulfiled; 
        bool completed;
    }
    struct Trade {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
    }

    // event Commited(address indexed initiator, address indexed counterparty, uint256 expiry);
    // event Completed(address indexed initiator, address indexed counterparty, uint256 index);

    modifier isOpen(Commitment memory commitment) 
    { 
        require(!commitment.fulfiled); 
        _; 
        } 
    modifier isAvailable(Commitment memory commitment) 
    { 
        require(!commitment.completed); 
        _; 
        } 
    modifier notEffective(Commitment memory commitment) 
    { 
        require(!commitment.active); 
        _; 
    }

    function commit(address counterparty, uint256 amount, address token, uint amount0, uint256 amount1, address token0, address token1, uint256 expiry, CommitmentType commitment_type) external {
        //make commitment
        Commitment memory commitment;
        TransferHelper._safeTransferFrom(token, msg.sender, address(this), amount);
        //require(commitment_type == CommitmentType.Locking || commitment_type == CommitmentType.Option || commitment_type == CommitmentType.Pure, "commitmentType is wrong");
        if (commitment_type == CommitmentType.Pure) {
            commitment = Commitment({
            initiator: msg.sender,
            counterparty: counterparty,
            amount: amount,
            token: token,
            expiry: expiry,
            trade: Trade({token0: address(0), token1:address(0), amount0:0, amount1:0}),
            commitment_type: CommitmentType.Pure,
            active: true, //immediately active for pure commitment
            fulfiled: false,
            completed: false
        });
        }
        if (commitment_type == CommitmentType.Locking) {
            TransferHelper._safeTransferFrom(token, msg.sender, address(this), amount);
            commitment = Commitment({
            initiator: msg.sender,
            counterparty: counterparty,
            amount: amount,
            token: token,
            expiry: expiry,
            trade: Trade({
                amount0: amount0,
                token0: token0,
                amount1: amount1,
                token1: token1
            }),
            commitment_type: CommitmentType.Locking,
            active: false, // active only after counterparty deposit his/her position
            fulfiled: false,
            completed: false
        });
        }  
        if (commitment_type == CommitmentType.Option) {
            TransferHelper._safeTransferFrom(token, msg.sender, address(this), amount0);
            commitment = Commitment({
            initiator: msg.sender,
            counterparty: counterparty,
            amount: amount,
            token: token,
            trade: Trade({
                amount0: amount0,
                amount1: amount1,
                token0: token0,
                token1: token1
            }),
            expiry: expiry,
            commitment_type: CommitmentType.Option,
            active: false, // active only after counterparty deposit his/her position
            fulfiled: false,
            completed: false
        });
        }
        commitments.push(commitment);
        //emit Commited(msg.sender, counterparty, expiry);
    }

    function fulfil_Type1(uint256 index) internal isOpen(commitments[index]) {
        require(commitments[index].expiry >= block.timestamp, "not expired");
        // simply retrieve after expiry, unless the counterparty has already fulfiled it
        commitments[index].fulfiled = true;
        commitments[index].completed = true;
        TransferHelper._safeTransfer(commitments[index].token, commitments[index].initiator, commitments[index].amount);
    }

    function fulfil_Type2(uint256 index) internal {
        // deposit your part as counterparty
        require(commitments[index].expiry < block.timestamp, "expired");

        address _token0 = commitments[index].trade.token0;
        address _token1 = commitments[index].trade.token1;
        uint256 _amount0 = (commitments[index]).trade.amount0;
        uint256 _amount1 = commitments[index].trade.amount1;

        // counterparty put in his position
        if (msg.sender == commitments[index].counterparty && !commitments[index].fulfiled) {
            // lock the commitment
            commitments[index].active = true;

            TransferHelper._safeTransferFrom(_token1, msg.sender, address(this), _amount1);    
        }
        // initiator put in his position and take back his commitment and counterparty's position
        if (commitments[index].active && !commitments[index].fulfiled && msg.sender == commitments[index].initiator) {

            commitments[index].fulfiled = true;
            // transfer in his position
            TransferHelper._safeTransferFrom(commitments[index].trade.token0, msg.sender, address(this), commitments[index].trade.amount0);       
            // take counterparty's position
            TransferHelper._safeTransfer(_token1, msg.sender, _amount1);
            //commitment
            TransferHelper._safeTransfer(commitments[index].token, msg.sender, commitments[index].amount);
        }
        // counterparty take initiator's position
        if (msg.sender == commitments[index].counterparty && commitments[index].fulfiled && !commitments[index].completed) {
            commitments[index].completed = true;
            TransferHelper._safeTransfer(_token0, address(this), _amount0);
        }
    }

    function fulfil_Type3(uint256 index) internal  {
        require(commitments[index].expiry < block.timestamp, "expired");

        address _token0 = commitments[index].trade.token0;
        address _token1 = commitments[index].trade.token1;
        uint256 _amount0 = (commitments[index]).trade.amount0;
        uint256 _amount1 = commitments[index].trade.amount1;

        if (msg.sender == commitments[index].counterparty && !commitments[index].fulfiled) {

                commitments[index].active = true;

                TransferHelper._safeTransferFrom(_token1, msg.sender, address(this), _amount1);    

                //commitment
                TransferHelper._safeTransfer(commitments[index].token, msg.sender, commitments[index].amount);
            }
            // initiator put in his position and take counterparty's position
            if (commitments[index].active && !commitments[index].fulfiled && msg.sender == commitments[index].initiator) {

                commitments[index].fulfiled = true;
                // transfer in his position
                TransferHelper._safeTransferFrom(_token0, msg.sender, address(this), _amount0);       
                // take counterparty's position
                TransferHelper._safeTransfer(_token1, msg.sender, _amount1);
                //commitment
            }
            // counterparty take initiator's position
            if (msg.sender == commitments[index].counterparty && commitments[index].fulfiled && !commitments[index].completed) {
                commitments[index].completed = true;
                TransferHelper._safeTransfer(_token0, address(this), _amount0);
            }
        }

    function fulfil(uint256 index) external  {
        if (commitments[index].commitment_type == CommitmentType.Pure) {
            fulfil_Type1(index);
        }
        if (commitments[index].commitment_type == CommitmentType.Locking) {
            fulfil_Type2(index);
        }  
        if (commitments[index].commitment_type == CommitmentType.Option) {
            fulfil_Type3(index);
        }
    }

    //get back commitment only if the deal is not completed, for completed deal commitement is already settled.
    // for Type1, the counterparty can collect the commitment anytime before the expiry, or the initiator collect after expiry
    function _retrieveC_1( uint256 index) private isAvailable(commitments[index]) {
        address _token = commitments[index].token;
        uint256 _amount = commitments[index].amount;

        if ( msg.sender == commitments[index].counterparty) {
            commitments[index].completed = true;
            TransferHelper._safeTransfer(_token, commitments[index].counterparty, _amount);
        }
        if (msg.sender == commitments[index].initiator && commitments[index].expiry >= block.timestamp) {
            commitments[index].completed = true;
            TransferHelper._safeTransfer(_token, commitments[index].initiator, _amount);
        }
    }
    // for Type2, the counterparty can collect the commitment if the intiitator doesnot settle after expiry, or the initiator get back before the commitment turns active
    function _retrieveC_2( uint256 index) private isAvailable(commitments[index]) {
        address _token = commitments[index].token;
        uint256 _amount = commitments[index].amount;
        if (!commitments[index].active) {
            
            commitments[index].completed = true;
            TransferHelper._safeTransfer(_token, commitments[index].initiator, _amount);
        }
        if (commitments[index].expiry >= block.timestamp && commitments[index].active) {
            commitments[index].completed = true;
            TransferHelper._safeTransfer(_token, commitments[index].counterparty, _amount);
        }
        
    }  
    // for Type3 only the initiator can get back the commitment anytime before the commitment becomes active.
    function _retrieveC_3( uint256 index) private notEffective(commitments[index]) isAvailable(commitments[index]) {
        commitments[index].completed = true;
        TransferHelper._safeTransfer(commitments[index].token, commitments[index].initiator, commitments[index].amount);
    }  

    function retrieveCommitment(uint256 index) external  {
        if (commitments[index].commitment_type == CommitmentType.Pure) {
            _retrieveC_1(index);
        }
        if (commitments[index].commitment_type == CommitmentType.Locking) {
            _retrieveC_2(index);
        }  
        if (commitments[index].commitment_type== CommitmentType.Option) {
            _retrieveC_3(index);
        }
    }


}