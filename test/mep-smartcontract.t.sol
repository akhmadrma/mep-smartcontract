// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
// Test for ProjectEscrow contract full workflow

//xxx Create Project, Create Milestone, Start Project, Start Milestone, Deposit Funds has been tested
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
            token
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
        uint amount = 100;
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
    }

    //start milestone failed
    function testStartMilestoneFailed() public {
        // uint projectId = defaultProjectId;
        // uint milestoneId = defaultMilestone1;
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

    //deposit funds success
    function testDepositeFundsSuccess() public {
        uint projectId = defaultProjectId;

        //create project, create milesotne, start project, start milestone
        testStartMilestoneSuccess();
        vm.startPrank(defaultClient);
        defaultToken.approve(address(escrow), 100);
        escrow.depositFunds(projectId, 100);
        vm.stopPrank();

        consoleHelperProject(projectId, defaultMilestone1, defaultMilestone2);
    }

    //deposit funds failed
    function testDepositeFundsFailed() public {
        uint projectId = defaultProjectId;

        //-------only client-------
        //create project, create milesotne, start project, start milestone
        testStartMilestoneSuccess();
        vm.startPrank(defaultWorker);
        defaultToken.approve(address(escrow), 100);
        revertHelper(
            ProjectEscrow.OnlyClient.selector,
            "only client can call this function"
        );
        escrow.depositFunds(projectId, 100);
        vm.stopPrank();

        // //-------amount 0-------
        // vm.startPrank(defaultClient);
        // defaultToken.approve(address(escrow), 100);
        // vm.expectRevert(ProjectEscrow.InvalidAmount.selector);
        // escrow.depositFunds(projectId, 0);
        // vm.stopPrank();

        // //-------amount more than project total amount-------
        // vm.startPrank(defaultClient);
        // defaultToken.approve(address(escrow), 100);
        // vm.expectRevert(ProjectEscrow.InvalidAmount.selector);
        // escrow.depositFunds(projectId, 1000);
        // vm.stopPrank();
    }

    // request payout success
    function testRequestPayoutSuccess() public {
        uint projectId = defaultProjectId;
        uint milestoneId = defaultMilestone1;
        uint amount = 100;
        //create project, create milesotne, start project, start milestone, deposit funds
        testStartMilestoneSuccess();
        vm.startPrank(defaultWorker);
        defaultToken.approve(address(escrow), amount);
        escrow.requestPayout(projectId, milestoneId, amount);
        vm.stopPrank();

        consoleHelperProject(projectId, milestoneId, milestoneId);
    }

    // request payout failed
    function testRequestPayoutFailed() public {
        uint projectId = defaultProjectId;
        uint milestoneId = defaultMilestone1;
        uint amount = 100;

        testDepositeFundsSuccess();
        vm.startPrank(defaultClient);
        revertHelper(
            ProjectEscrow.OnlyWorker.selector,
            "only worker can call this function"
        );
        escrow.requestPayout(projectId, milestoneId, amount);
        vm.stopPrank();

        //-------milestone not onprogress------wadwadawdaw
        vm.startPrank(defaultWorker);
        revertHelper(
            ProjectEscrow.InvalidState.selector,
            "milestone is not onprogress"
        );
        escrow.requestPayout(projectId, defaultMilestone2, amount);
        vm.stopPrank();

        //-------amount 0 or more than milestone amount-------
        vm.startPrank(defaultWorker);
        revertHelper(
            ProjectEscrow.InvalidAmount.selector,
            "amount is 0 or more than milestone amount"
        );
        escrow.requestPayout(projectId, milestoneId, 0);
        vm.stopPrank();
    }

    function revertHelper(bytes4 selector, string memory message) public {
        vm.expectRevert(abi.encodeWithSelector(selector, message));
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

    function consoleHelperProject(
        uint projectId,
        uint milestone1,
        uint milestone2
    ) public view {
        ProjectEscrow.Project memory p = getProjectDetails(projectId);
        ProjectEscrow.Milestone memory m1 = getMilestoneDetails(
            projectId,
            milestone1
        );
        ProjectEscrow.Milestone memory m2 = getMilestoneDetails(
            projectId,
            milestone2
        );

        console.log(
            "defaultToken.balanceOf(defaultClient) : %s",
            defaultToken.balanceOf(defaultClient)
        );
        console.log(
            "defaultToken.balanceOf(address(escrow)) : %s",
            defaultToken.balanceOf(address(escrow))
        );
        console.log(
            "defaultToken.balanceOf(defaultWorker) : %s",
            defaultToken.balanceOf(defaultWorker)
        );

        console.log("----------projectId  : %s", projectId);
        console.log(" status  : %s", uint(p.status));
        console.log(" totalAmount  : %s", p.totalAmount);
        console.log(" fundsDeposited  : %s", p.fundsDeposited);
        console.log(" worker  : %s", p.worker);
        console.log(" client  : %s", p.client);
        console.log(" token  : %s", p.token);
        for (uint i = 0; i < p.milestoneIds.length; i++) {
            console.log(" milestoneIds[%s]  : %s", i, p.milestoneIds[i]);
        }
        console.log("----------milestone1  : %s", milestone1);
        console.log(" status  : %s", uint(m1.status));
        console.log(" amount  : %s", m1.amount);
        console.log(" payoutAmount  : %s", m1.payoutAmount);
        console.log(" payoutResponse  : %s", uint(m1.payoutResponse));
        console.log(" milestoneResponse  : %s", uint(m1.milestoneResponse));
        console.log(" timestamp  : %s", m1.timestamp);
        console.log("----------milestone2  : %s", milestone2);
        console.log(" status  : %s", uint(m2.status));
        console.log(" amount  : %s", m2.amount);
        console.log(" payoutAmount  : %s", m2.payoutAmount);
        console.log(" payoutResponse  : %s", uint(m2.payoutResponse));
        console.log(" milestoneResponse  : %s", uint(m2.milestoneResponse));
        console.log(" timestamp  : %s", m2.timestamp);
    }
}
