// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Time Banking System
 * @dev A blockchain-based platform for exchanging services based on time rather than money
 * @author TimeBank Development Team
 */
contract TimeBank {
    
    // Structs
    struct User {
        uint256 timeBalance;
        uint256 reputation;
        bool isRegistered;
        string skillSet;
        uint256 servicesCompleted;
        uint256 lastActivity;
    }
    
    struct ServiceRequest {
        uint256 id;
        address requester;
        address provider;
        string serviceDescription;
        uint256 timeRequired;
        uint256 timestamp;
        ServiceStatus status;
        bool emergencyRequest;
    }
    
    struct DisputeCase {
        uint256 serviceId;
        address complainant;
        string reason;
        uint256 timestamp;
        bool resolved;
        uint256 votes;
    }
    
    // Enums
    enum ServiceStatus { Open, Accepted, InProgress, Completed, Disputed, Cancelled }
    
    // State variables
    mapping(address => User) public users;
    mapping(uint256 => ServiceRequest) public serviceRequests;
    mapping(uint256 => DisputeCase) public disputes;
    mapping(address => mapping(uint256 => bool)) public hasVotedOnDispute;
    
    uint256 public nextServiceId = 1;
    uint256 public nextDisputeId = 1;
    uint256 public constant INITIAL_TIME_TOKENS = 5; // New users get 5 hours
    uint256 public constant TOKEN_EXPIRY_DAYS = 365; // Tokens expire after 1 year
    uint256 public emergencyPoolBalance;
    
    address public owner;
    
    // Events
    event UserRegistered(address indexed user, string skillSet);
    event ServiceRequested(uint256 indexed serviceId, address indexed requester, uint256 timeRequired);
    event ServiceAccepted(uint256 indexed serviceId, address indexed provider);
    event ServiceCompleted(uint256 indexed serviceId, address indexed provider, address indexed requester);
    event DisputeRaised(uint256 indexed disputeId, uint256 indexed serviceId, address indexed complainant);
    event TokensTransferred(address indexed from, address indexed to, uint256 amount);
    event EmergencyPoolContribution(address indexed contributor, uint256 amount);
    
    // Modifiers
    modifier onlyRegistered() {
        require(users[msg.sender].isRegistered, "User not registered");
        _;
    }
    
    modifier onlyServiceParticipant(uint256 _serviceId) {
        ServiceRequest storage request = serviceRequests[_serviceId];
        require(
            msg.sender == request.requester || msg.sender == request.provider,
            "Only service participants can call this function"
        );
        _;
    }
    
    modifier validService(uint256 _serviceId) {
        require(_serviceId > 0 && _serviceId < nextServiceId, "Invalid service ID");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Register a new user in the time banking system
     * @param _skillSet Description of user's skills and services they can offer
     */
    function registerUser(string memory _skillSet) external {
        require(!users[msg.sender].isRegistered, "User already registered");
        require(bytes(_skillSet).length > 0, "Skill set cannot be empty");
        
        users[msg.sender] = User({
            timeBalance: INITIAL_TIME_TOKENS,
            reputation: 100, // Starting reputation score
            isRegistered: true,
            skillSet: _skillSet,
            servicesCompleted: 0,
            lastActivity: block.timestamp
        });
        
        emit UserRegistered(msg.sender, _skillSet);
    }
    
    /**
     * @dev Create a new service request
     * @param _serviceDescription Description of the service needed
     * @param _timeRequired Number of time tokens (hours) required for the service
     * @param _isEmergency Whether this is an emergency request (uses community pool)
     */
    function requestService(
        string memory _serviceDescription,
        uint256 _timeRequired,
        bool _isEmergency
    ) external onlyRegistered returns (uint256) {
        require(_timeRequired > 0, "Time required must be greater than 0");
        require(bytes(_serviceDescription).length > 0, "Service description cannot be empty");
        
        if (!_isEmergency) {
            require(users[msg.sender].timeBalance >= _timeRequired, "Insufficient time balance");
        } else {
            require(emergencyPoolBalance >= _timeRequired, "Insufficient emergency pool balance");
        }
        
        uint256 serviceId = nextServiceId++;
        
        serviceRequests[serviceId] = ServiceRequest({
            id: serviceId,
            requester: msg.sender,
            provider: address(0),
            serviceDescription: _serviceDescription,
            timeRequired: _timeRequired,
            timestamp: block.timestamp,
            status: ServiceStatus.Open,
            emergencyRequest: _isEmergency
        });
        
        emit ServiceRequested(serviceId, msg.sender, _timeRequired);
        return serviceId;
    }
    
    /**
     * @dev Accept a service request and become the provider
     * @param _serviceId ID of the service request to accept
     */
    function acceptService(uint256 _serviceId) 
        external 
        onlyRegistered 
        validService(_serviceId) 
    {
        ServiceRequest storage request = serviceRequests[_serviceId];
        require(request.status == ServiceStatus.Open, "Service not available");
        require(request.requester != msg.sender, "Cannot accept your own service request");
        require(users[msg.sender].reputation >= 50, "Insufficient reputation to accept services");
        
        request.provider = msg.sender;
        request.status = ServiceStatus.Accepted;
        
        // Lock the time tokens
        if (!request.emergencyRequest) {
            users[request.requester].timeBalance -= request.timeRequired;
        } else {
            emergencyPoolBalance -= request.timeRequired;
        }
        
        users[msg.sender].lastActivity = block.timestamp;
        
        emit ServiceAccepted(_serviceId, msg.sender);
    }
    
    /**
     * @dev Complete a service and transfer time tokens
     * @param _serviceId ID of the service to complete
     */
    function completeService(uint256 _serviceId) 
        external 
        onlyServiceParticipant(_serviceId) 
        validService(_serviceId) 
    {
        ServiceRequest storage request = serviceRequests[_serviceId];
        require(
            request.status == ServiceStatus.Accepted || request.status == ServiceStatus.InProgress,
            "Service not in progress"
        );
        
        request.status = ServiceStatus.Completed;
        
        // Transfer time tokens to provider
        users[request.provider].timeBalance += request.timeRequired;
        users[request.provider].servicesCompleted++;
        users[request.provider].reputation += 5; // Boost reputation for completed service
        users[request.provider].lastActivity = block.timestamp;
        
        // Update requester's last activity
        users[request.requester].lastActivity = block.timestamp;
        
        emit ServiceCompleted(_serviceId, request.provider, request.requester);
        emit TokensTransferred(request.requester, request.provider, request.timeRequired);
    }
    
    /**
     * @dev Contribute time tokens to the emergency community pool
     * @param _amount Number of time tokens to contribute
     */
    function contributeToEmergencyPool(uint256 _amount) external onlyRegistered {
        require(_amount > 0, "Contribution must be greater than 0");
        require(users[msg.sender].timeBalance >= _amount, "Insufficient time balance");
        
        users[msg.sender].timeBalance -= _amount;
        emergencyPoolBalance += _amount;
        users[msg.sender].reputation += _amount * 2; // Double reputation boost for community contributions
        
        emit EmergencyPoolContribution(msg.sender, _amount);
    }
    
    // View functions
    function getUserProfile(address _user) external view returns (
        uint256 timeBalance,
        uint256 reputation,
        string memory skillSet,
        uint256 servicesCompleted,
        uint256 lastActivity
    ) {
        User storage user = users[_user];
        require(user.isRegistered, "User not registered");
        
        return (
            user.timeBalance,
            user.reputation,
            user.skillSet,
            user.servicesCompleted,
            user.lastActivity
        );
    }
    
    function getServiceRequest(uint256 _serviceId) external view validService(_serviceId) returns (
        address requester,
        address provider,
        string memory serviceDescription,
        uint256 timeRequired,
        ServiceStatus status,
        bool emergencyRequest
    ) {
        ServiceRequest storage request = serviceRequests[_serviceId];
        return (
            request.requester,
            request.provider,
            request.serviceDescription,
            request.timeRequired,
            request.status,
            request.emergencyRequest
        );
    }
    
    function getEmergencyPoolBalance() external view returns (uint256) {
        return emergencyPoolBalance;
    }
    
    function getTotalServices() external view returns (uint256) {
        return nextServiceId - 1;
    }
    
    // Helper function to check if tokens have expired (simplified version)
    function hasExpiredTokens(address _user) external view returns (bool) {
        return block.timestamp > users[_user].lastActivity + (TOKEN_EXPIRY_DAYS * 1 days);
    }
}
