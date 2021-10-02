Contract CommitmentFactory 
{ 
  Enum CommitmentType(Pure, Locking, Option)

  struct Commitment { 
    address payable initiator; 
    address payable counterparty; 
    uint256 amount; 
    address token0; 
    address token1; 
    uint256 expiry; 
    CommitmentType commitement_type; 
    bool active; 
    bool exercised; }
    
    //some mapping, TBC
    mapping ();

    Event Commited(address to, address from, uint256 expiry);

    modifier isExercised(Commitement commitment) public 
    { 
      require(commitment.exercised); 
      _; } 
    modifier isActive(Commitement commitment) public 
    { 
      require(commitement.active); 
      _; 
    }

    modifier isExpiry(Commitement commitment) public 
    { 
      require(commitement.expiry >= block.timestamp); 
      _; 
    }

    modifier isInitator(Commitement commitment) public 
    { 
      require(msg.sender == commitment.initiator); 
      _; 
    }

    modifier isCounterparty(Commitement commitment) public 
    { 
      require(msg.sender == commitment.counterparty);
      _; 
    } 
      
    function _initiate(address counterparty, uint256 amount, adress token0, address token1, uint256b expiry) private 
    { 
      // private initate function to be used in the public func initate_TypeX 
    }

    function initiate_Type1() public 
    { 
      // create a pure commitement 
    }

    function initate_Type2() public 
    { 
      // create a commitment that once settled, commitement amount go back to initiator 
    } 
    
    function initate_Type3() public 
    { 
      // create a commitment that once active, commitement goes immediately to counterparty
    }

    function retrive_onExpiry(Commitement commitment) isExpiry(Commitement commitment)

    }
