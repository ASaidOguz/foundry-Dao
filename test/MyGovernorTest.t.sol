// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test,console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGoverner.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";


contract MyGovernorTest is Test {
    MyGovernor public governor;
    Box public box;
    TimeLock public timelock;
    GovToken public govToken;
    
    // we kept empty so anyone can propose and execute...
    address[] public proposers;
    address[] public executers;
    uint256[] public values;
    bytes[] public calldatas;
    address[] public targets;

    address public USER=makeAddr("user");
    uint256 public constant INITIAL_SUPPLY= 100 ether;
    uint256 public constant MIN_DELAY=3600 ;// 1 Hour
    uint256 public constant VOTING_DELAY= 1; //how many blocks dat vote is active;
    uint256 public constant VOTING_PERIOD= 50400; 
    function setUp() public{
        govToken=new GovToken();
        govToken.mint(USER,INITIAL_SUPPLY);
        
        vm.startPrank(USER);
        govToken.delegate(USER);
        timelock=new TimeLock(MIN_DELAY,proposers,executers);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole=timelock.PROPOSER_ROLE();
        bytes32 executorRole=timelock.EXECUTOR_ROLE();
        bytes32 adminRole=timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole,address(governor));
        timelock.grantRole(executorRole,address(0));
        timelock.revokeRole(adminRole,USER);
        vm.stopPrank();

        box=new Box();

        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public{
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceupdatesBox() public{
        uint256 newNumber=689;
        string memory description="1 stored in box!";
        //this calldata represents which function we will call if the governance accepts!
        bytes memory encodedFunctionCall=abi.encodeWithSignature("store(uint256)",newNumber);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // 1. Propose to DAO;
        uint256 proposalId=governor.propose(targets,values,calldatas,description);
        // 2. Check propose state
        console.log("Propose state:",uint256(governor.state(proposalId)));

        vm.warp(block.timestamp+VOTING_DELAY+1);
        vm.roll(block.number+VOTING_DELAY+1);

        console.log("Propose state:",uint256(governor.state(proposalId)));

        // 2. cast vote 

        string memory reason="Just because I can";
        // support argument is enum -> 
        uint8 voteSupport=1;
        vm.startPrank(USER);
        governor.castVoteWithReason(proposalId,voteSupport,reason);
        vm.warp(block.timestamp+VOTING_PERIOD+1);
        vm.roll(block.number+VOTING_PERIOD+1);

        // 3. Queue TX;
        bytes32 descriptionhash=keccak256(abi.encodePacked(description));
        governor.queue(targets,values,calldatas,descriptionhash);
        
        vm.warp(block.timestamp+MIN_DELAY+1);
        vm.roll(block.number+MIN_DELAY+1);
        // 4. Execute ;
        governor.execute(targets,values,calldatas,descriptionhash);

        assertEq(box.getNumber(),newNumber);
        console.log("Box number new value:",box.getNumber());

    }
}