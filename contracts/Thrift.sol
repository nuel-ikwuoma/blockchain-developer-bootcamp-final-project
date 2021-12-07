// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

contract ThriftManager {
    // tracks the thrift count explicitly and ID implicitly
    uint256 thriftCount;

    // defines the thrift struct
    struct Thrift {
        uint256 ID;
        uint256 maxParticipants;
        uint256 minStake;
        mapping(address => bool) contributors;
        mapping(address => uint256) contributions;
    }
    function createThrift() external returns(bool) {

    }

    function joinThrift() external returns(bool) {

    }

    function contributeToThrift() external returns(bool) {

    }

    function closeThrift() external returns(bool) {

    }

    function thriftValid() external returns(bool){
        
    }
}