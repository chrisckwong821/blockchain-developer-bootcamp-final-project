pragma solidity >=0.8.0 <0.9.0;

interface ICommitmentPool
{ 
    event Commited(address indexed initiator, address indexed counterparty, uint256 expiry);
    event Completed(address indexed initiator, address indexed counterparty, uint256 index);

    function commit(address counterparty, uint256 expiry, uint256 commitment_type) external;

    function fulfil(address initiator, address counterparty, uint256 index) external;
        // fulfil as an initiator // counterparty

    function retrieveCommitment(address initiator, address counterparty, uint256 index) external;

    function getCommitment_length(address initiator, address counterparty) external view returns (uint256);
}
