// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
// Test for ProjectEscrow contract full workflow

//xxx Create Project, Create Milestone, Start Project, Start Milestone has been tested
//todo : test the rest of the functions

import {Test} from "forge-std/Test.sol";
import {ProjectEscrow} from "../src/mep-smartcontract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console} from "forge-std/console.sol";

contract MockERC20 {
    string public name = "MockToken";
    string public symbol = "MTK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient");
        require(allowance[from][msg.sender] >= amount, "Not allowed");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract ProjectEscrowFullFlowTest is Test {
    ProjectEscrow public escrow;
    MockERC20 public defaultToken;

    address public defaultClient = address(0x100);
    address public defaultWorker = address(0x200);

    uint256 public defaultProjectId = 1;
    uint256 public defaultMilestone1 = 0;
    uint256 public defaultMilestone2 = 1;

    function setUp() public {
        escrow = new ProjectEscrow();
        defaultToken = new MockERC20();

        // Mint tokens to client
        defaultToken.mint(defaultClient, 1000);
    }

    // create project success
    function testCreateProjectSuccess() public {
        uint256 projectId = defaultProjectId;
        address client = defaultClient;
        address token = address(defaultToken);

        vm.startPrank(defaultWorker);

        vm.expectEmit(true, true, true, true);
        emit ProjectEscrow.ProjectCreated(
            projectId,
            client,
            defaultWorker,
            token,
            ProjectEscrow.Status.PENDING
        );
        escrow.createProject(projectId, client, token);

        vm.stopPrank();
    }

    //create project failed
    function testCreateProjectFailed() public {
        // -----project already created----
        testCreateProjectSuccess();
        vm.startPrank(defaultWorker);
        vm.expectRevert(ProjectEscrow.AlreadyExists.selector);
        escrow.createProject(
            defaultProjectId,
            defaultClient,
            address(defaultToken)
        );
        vm.stopPrank();
        //-----client is zero address----
        // vm.startPrank(defaultWorker);
        // vm.expectRevert(ProjectEscrow.ZeroAddress.selector);
        // escrow.createProject(projectId, address(0), address(token));
        // vm.stopPrank();
    }

    //set milestone success
    function testCreateMilestoneSuccess() public {
        uint projectId = defaultProjectId;
        uint milestoneId = defaultMilestone1;
        uint amount = 100;

        testCreateProjectSuccess();

        vm.startPrank(defaultWorker);
        vm.expectEmit(true, true, true, true);
        emit ProjectEscrow.MilestoneCreated(projectId, milestoneId, amount);
        escrow.createMilestone(projectId, milestoneId, amount);

        //create milestone2
        vm.expectEmit(true, true, true, true);
        emit ProjectEscrow.MilestoneCreated(
            projectId,
            defaultMilestone2,
            amount
        );
        escrow.createMilestone(projectId, defaultMilestone2, amount);
        vm.stopPrank();
    }

    //create milestone failed
    function testCreateMilestoneFailed() public {
        // //-----only defaultWorker------
        // testCreateProjectSuccess();
        // vm.startPrank(defaultClient);
        // vm.expectRevert(ProjectEscrow.OnlyWorker.selector);
        // escrow.createMilestone(defaultProjectId, defaultMilestone1, 100);
        // vm.stopPrank();

        // // -----milestone already created-----
        // //create milestone 1,2
        // testCreateMilestoneSuccess();
        // //create existing milestone
        // vm.startPrank(defaultWorker);
        // vm.expectRevert(ProjectEscrow.AlreadyExists.selector);
        // escrow.createMilestone(defaultProjectId, defaultMilestone2, 100);
        // vm.stopPrank();

        //-----amount is zero-----
        //create project
        testCreateProjectSuccess();
        //set amount zero
        vm.startPrank(defaultWorker);
        vm.expectRevert(ProjectEscrow.InvalidAmount.selector);
        escrow.createMilestone(defaultProjectId, defaultMilestone1, 0);
        vm.stopPrank();
    }

    //start project success
    function testStartProjectSuccess() public {
        uint projectId = defaultProjectId;
        uint amount = 500;
        //create project && milestone
        testCreateMilestoneSuccess();

        //start project
        vm.startPrank(defaultClient);
        // approve escrow to spend client's tokens
        defaultToken.approve(address(escrow), amount);

        vm.expectEmit(true, true, true, true);
        emit ProjectEscrow.ProjectStarted(projectId, amount);
        escrow.startProject(projectId, amount);
        vm.stopPrank();
    }

    //start project failed
    function testStartProjectFailed() public {
        uint projectId = defaultProjectId;
        uint amount = 100;
        //create project && milestone
        testCreateMilestoneSuccess();

        //-------only Client---------
        //start project
        vm.startPrank(defaultWorker);
        // approve escrow to spend client's tokens
        defaultToken.approve(address(escrow), amount);

        vm.expectRevert(ProjectEscrow.OnlyClient.selector);
        escrow.startProject(projectId, amount);
        vm.stopPrank();

        //-------Amount 0---------
        //start project
        vm.startPrank(defaultWorker);
        // approve escrow to spend client's tokens
        defaultToken.approve(address(escrow), amount);

        vm.expectRevert(ProjectEscrow.OnlyClient.selector);
        escrow.startProject(projectId, 0);
        vm.stopPrank();
    }

    //start milestone
    function testStartMilestoneSuccess() public {
        uint projectId = defaultProjectId;
        uint milestoneId = defaultMilestone1;
        // create project, create milesotne, start project
        testStartProjectSuccess();

        vm.startPrank(defaultWorker);
        vm.expectEmit(true, true, true, true);
        emit ProjectEscrow.MilestoneStarted(projectId, milestoneId);
        escrow.startMilestone(projectId, milestoneId);
        vm.stopPrank();

        ProjectEscrow.Milestone memory milestone = getMilestoneDetails(projectId, milestoneId);
        console.logString("milestone status");
        console.logUint(uint(milestone.status));
        console.logString("milestone amount");
        console.logUint(milestone.amount);

        ProjectEscrow.Project memory project = getProjectDetails(projectId);
        console.logString("project status");
        console.logUint(uint(project.status));
        console.logString("project funds deposited");
        console.logUint(project.fundsDeposited);
        console.logString("project total amount");
        console.logUint(project.totalAmount);
    }

    //start milestone failed
    function testStartMilestoneFailed() public {
        uint projectId = defaultProjectId;
        uint milestoneId = defaultMilestone1;

        // //---only worker---
        // // create project, create milesotne, start project
        // testStartProjectSuccess();
        // vm.startPrank(defaultClient);
        // vm.expectRevert(ProjectEscrow.OnlyWorker.selector);
        // escrow.startMilestone(projectId, milestoneId);
        // vm.stopPrank();

        // //---milestone not pending or rejected or project not onprogress---
        // // create project, create milesotne, start project
        // // testCreateProjectSuccess(); // make project status pending
        // testStartMilestoneSuccess(); // make milestone status ONPROGRES
        // vm.startPrank(defaultWorker);
        // vm.expectRevert(ProjectEscrow.InvalidState.selector);
        // escrow.startMilestone(projectId, milestoneId);
        // vm.stopPrank();
    }





    //helper
    function getMilestoneDetails(
        uint projectId,
        uint milestoneId
    ) public view returns (ProjectEscrow.Milestone memory) {
        return escrow.getMilestoneDetails(projectId, milestoneId);
    }
    //helper
    function getProjectDetails(
        uint projectId
    ) public view returns (ProjectEscrow.Project memory) {
        return escrow.getProjectDetails(projectId);
    }
}
