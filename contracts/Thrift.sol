// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

contract ThriftManager {
    // address with priviledge to adjust contract parameters
    address admin;

    // tracks the thrift count explicitly and ID implicitly
    uint256 nextThriftId;

    // lock to guard reentrancy
    bool lock;

    // constructor
    constructor() {
        admin = _msgSender();
    }

    // defines the thrift struct
    struct Thrift {
        uint256 id;
        uint256 maxParticipants;
        uint256 numParticipants;            // number of participants in the thrift
        uint256 minStake;
        uint256 roundAmount;                // per participant contribution amount in a round
        uint256 curRound;                   // tracks the current round count
        uint256 roundContributionCount;     // track participants count that has contributed for every round
        uint256 roundPeriod;                // time allowed for every round
        uint startTime;                     // tracks time when thrift kickstarts
        address creator;                    // address that started the thrift
        bool start;                         // starts when max participants is reached
        bool completed;                     // completed when all participants funds has been disbursed or a paricipant defaults oncontribution
        mapping(uint256 => address payable) contributorsRank;
        mapping(address => bool) contributors;
        mapping(address => uint256) hasStaked;
        mapping(uint256 => uint256) roundCompletionTime;                                // tracks when rounds are completed
        mapping(uint256 => uint256) numContributionPerRound;                             // tracks number of conributors for any given round
        mapping(uint256 => bool) roundCompleted;                                        // track round completion incrementally
        mapping(uint256 => mapping(address => uint256)) roundContributionAmount;        // track  participants contribution for a given round
    }

    mapping(uint256 => Thrift) public thrifts;
    mapping(uint256 => uint256) thriftMinStake;                                         // tracks minimum thrift stake amount

    // EVENTS
    //
    event ThriftCreated(uint256 id, uint256 maxParticipants, uint256 minStake, uint256 rouundAmt, uint256 createdAt);
    event ContributorJoined(uint256 id, address contribAddress);
    event CloseThrift(uint256 id);
    event EndDefaultingThrift(uint256 id);

    // start a new thrift
    function createThrift(uint256 _maxParticipants, uint256 _roundAmount,uint256 _roundPeriod)
        payable
        external
        returns(uint256, uint256, uint256, uint256, uint256) {
            require(_maxParticipants > 1 && _maxParticipants <= 10, "Only two to ten participants allowed");
            require(_roundAmount > 0, "Round contribution must exceed zero");
            require(_roundPeriod > 0, "Round period must exceed zero");
            Thrift storage newThrift = thrifts[nextThriftId];
            uint _thriftID = nextThriftId;
            newThrift.id = _thriftID;
            newThrift.maxParticipants = _maxParticipants;
            newThrift.numParticipants = 1;
            newThrift.roundAmount = _roundAmount;
            newThrift.creator = _msgSender();
            newThrift.roundPeriod = _roundPeriod;
            newThrift.startTime = _timeStamp();
            uint256 _minStake = _maxParticipants * _roundAmount;
            newThrift.minStake = _minStake;
            thriftMinStake[nextThriftId] = _minStake;
            // creator should deposit minimum stake
            require(_msgValue() >= _minStake, "Send Ether amount equivalent to minimum stake");
            newThrift.contributorsRank[0] = payable(_msgSender());
            newThrift.contributors[_msgSender()] = true;
            newThrift.hasStaked[_msgSender()] = _msgValue();
            nextThriftId++;
            emit ThriftCreated(_thriftID, _maxParticipants, _minStake, _roundAmount, _timeStamp());
            return (_thriftID, _maxParticipants, _minStake, _roundAmount, _timeStamp());
    }

    //  join a thrift with minimum stake deposit
    function joinThrift(uint256 _thriftID) payable external thriftExists(_thriftID) thriftNotStarted(_thriftID) returns(bool) {
        require(!_isContributor(_thriftID, _msgSender()), "Address already a thrift contributor");
        require(!_hasStarted(_thriftID), "Thrift already started");
        Thrift storage thrift = thrifts[_thriftID];
        uint256 position = thrift.numParticipants;
        thrift.numParticipants += 1;
        require(_msgValue() >= thrift.minStake, "Send Ether amount equivalent to minimum stake");
        thrift.contributorsRank[position] = payable(_msgSender());
        thrift.hasStaked[_msgSender()] = _msgValue();
        // check if maximum participants is reached
        if(thrift.numParticipants < (thrift.maxParticipants)) {
            return true;
        }else if(thrift.numParticipants == (thrift.maxParticipants)) {  // start thrift once max participantis reached
            thrift.start = true;
            emit ContributorJoined(_thriftID, _msgSender());
            return true;
        }else {                                                         // revert if max participants exceeded
            revert("Max participants reached already");
        }
    }

    // adding contribution to a thrift round
    function contributeToThrift(uint256 _thriftID) payable external thriftExists(_thriftID) returns(bool) {
        require(_isContributor(_thriftID, _msgSender()), "Address not a contributor");
        require(_hasStarted(_thriftID), "Thrift contribution is yet to start");
        require(!_hasCompleted(_thriftID), "Thrift has been completed");
        Thrift storage thrift = thrifts[_thriftID];
        uint256 numParticipants = thrift.numParticipants;
        uint256 curRound = thrift.curRound;
        require(thrift.roundContributionAmount[curRound][_msgSender()] == 0, "Cannot contribute twice to a round");
        require(_msgValue() > 0 && _msgValue() >= thrift.roundAmount, "Ether sent must exceed zero and rount amount");
        // account for rouund period and close thrift if its been ellapsed
        if(curRound == 0) {
            bool periodEllapsed = _timeStamp() > thrift.startTime + thrift.roundPeriod;
            if(periodEllapsed) {
                emit EndDefaultingThrift(_thriftID);
                return !_endDefaultingThrift(_thriftID, curRound, numParticipants);
            }
        }else {
            bool periodEllapsed = _timeStamp() > thrift.roundCompletionTime[curRound-1] + thrift.roundPeriod;
            if(periodEllapsed) {
                emit EndDefaultingThrift(_thriftID);
                return !_endDefaultingThrift(_thriftID, curRound, numParticipants);
            }
        }
        thrift.roundContributionCount += 1;
        thrift.roundContributionAmount[curRound][_msgSender()] = _msgValue();
        thrift.numContributionPerRound[curRound] += 1;
        
        // last contribution sholud update relevant thrift state information and disburse funds
        if(thrift.roundContributionCount == numParticipants) {
            thrift.roundCompleted[curRound] = true;
            thrift.roundCompletionTime[curRound] = _timeStamp();
            // disburse funds to round collector and update round 
            address recipientContrib = thrift.contributorsRank[curRound];
            uint256 amount = thrift.roundAmount * numParticipants;
            _sendViaCall(recipientContrib, amount);
            thrift.curRound += 1;
        }
        // thrift is completed
        if(++curRound == numParticipants) {
            emit CloseThrift(_thriftID);
            thrift.completed = true;
        }
        return true;
    }

    // anyone can close thrift when 
    // 1. thrift is not yet completed and,
    // 2. block timestamp has exceeded the deadline
    function closeThrift(uint256 _thriftID) external returns(bool) {
        Thrift storage thrift = thrifts[_thriftID];
        bool completed = thrift.completed;
        bool deadline = _timeStamp() > thrift.startTime + (thrift.roundPeriod * thrift.numParticipants);
        require(!completed && deadline, "Thrift already completed or deadline not exceeded");
        emit EndDefaultingThrift(_thriftID);
        return _endDefaultingThrift(_thriftID, thrift.curRound, thrift.numParticipants);
    }

    // get thrift minStake
    function getMinStake(uint256 _thriftID) thriftExists(_thriftID) external view returns(uint256) {
        return thriftMinStake[_thriftID];
    }

    // external agent can check if a thrift exists in the contract
    function thriftValid(uint256 _thriftID) external view returns(bool){
        return _thriftID < nextThriftId;
    }


    // CONTRACT HELPERS
    //
    function _msgSender() internal view returns(address) {
        return msg.sender;
    }

    function _msgValue() internal view returns(uint256) {
        return msg.value;
    }

    function _timeStamp() internal view returns(uint256) {
        return block.timestamp;
    }

    function _isContributor(uint256 _thriftID, address _contributor) internal view thriftExists(_thriftID) returns(bool) {
        Thrift storage thrift = thrifts[_thriftID];
        return thrift.contributors[_contributor];
    }

    function _hasStarted(uint256 _thriftID) internal view thriftExists(_thriftID) returns(bool) {
        Thrift storage thrift = thrifts[_thriftID];
        return thrift.start;
    }

    function _hasCompleted(uint256 _thriftID) internal view thriftExists(_thriftID) returns(bool) {
        Thrift storage thrift = thrifts[_thriftID];
        return thrift.completed;
    }

    function _endDefaultingThrift(uint256 _thriftID, uint256 _curRound, uint256 _numParticipants) internal thriftExists(_thriftID) returns(bool) {
        Thrift storage thrift = thrifts[_thriftID];
        uint256 numRoundContributors = thrift.numContributionPerRound[_curRound];
        uint256 penaltyFee = (thrift.minStake * _numParticipants) / numRoundContributors;
        for(uint i=0; i<_numParticipants; i++) {
            address recipientContrib = thrift.contributorsRank[i];
            uint256 contributorAmount = thrift.roundContributionAmount[_curRound][recipientContrib];
            if(contributorAmount > 0) {
                uint256 payoutAmount = contributorAmount + penaltyFee;
                _sendViaCall(recipientContrib, payoutAmount);
            }
        }
        thrift.completed = true;
        return true;
    }
    

    function _sendViaCall(address _to, uint256 amount) public payable {
        require(!lock, "re-rentrant calls not allowed");
        lock = true;
        (bool sent,) = payable(_to).call{value: amount}("");
        lock = false;
        require(sent, "Failed to send Ether");
    }

    // CONTRACT MODIFIERS
    //
    modifier onlyAdmin() {
        require(_msgSender() == admin, "Sender is not an admin");
        _;
    }

    modifier thriftExists(uint256 _thriftID) {
        require(_thriftID < nextThriftId, "Thrift not existence");
        _;
    }

    modifier thriftNotStarted(uint256 _thriftID) {
        require(!thrifts[_thriftID].start, "Thrift closed to new participants");
        _;
    }

    // prevent ether transfers for unknown contract call */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
    fallback() payable external {
        revert("Unknown contract call ETHER transfer rejected");
    }

    // prevent forceful ETHER transfers on empty msg.data
    receive() external payable {
        revert("Forceful ETHER transfer rejected");
    }
}