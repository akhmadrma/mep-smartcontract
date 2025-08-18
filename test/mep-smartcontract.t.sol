// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
// Test for ProjectEscrow contract full workflow

//xxx this just outline for the test, need to be updated
//todo : configure each name of the function

import {Test} from "forge-std/Test.sol";
import {ProjectEscrow} from "../src/mep-smartcontract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockERC20 {
    string public name = "MockToken";
    string public symbol = "MTK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

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

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
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
    MockERC20 public token;

    address public client = address(0x100);
    address public worker = address(0x200);

    uint256 public projectId = 1;
    uint256 public milestone1 = 0;
    uint256 public milestone2 = 1;

    function setUp() public {
        escrow = new ProjectEscrow();
        token = new MockERC20();

        // Mint tokens to client
        token.mint(client, 1000 ether);
    }

    function testFullProjectFlow() public {
        // 1. Client creates a project
        vm.startPrank(client);

        // Simulate project creation
        // Assume function: createProject(uint256 projectId, address worker, address token, uint256 totalAmount)
        escrow.createProject(projectId, worker, address(token), 500 ether);

        // 2. Client adds milestones
        // Assume function: addMilestone(uint256 projectId, uint256 milestoneId, uint256 amount)
        escrow.addMilestone(projectId, milestone1, 200 ether);
        escrow.addMilestone(projectId, milestone2, 300 ether);

        // 3. Client deposits funds
        token.approve(address(escrow), 500 ether);
        escrow.depositFunds(projectId, 500 ether);

        // 4. Worker requests milestone approval
        vm.stopPrank();
        vm.startPrank(worker);
        // Assume function: requestMilestoneApproval(uint256 projectId, uint256 milestoneId)
        escrow.requestMilestoneApproval(projectId, milestone1);

        // 5. Client approves milestone
        vm.stopPrank();
        vm.startPrank(client);
        escrow.approveMilestone(projectId, milestone1);

        // 6. Worker requests payout for milestone
        vm.stopPrank();
        vm.startPrank(worker);
        escrow.requestPayout(projectId, milestone1);

        // 7. Client approves payout
        vm.stopPrank();
        vm.startPrank(client);
        escrow.approvePayout(projectId, milestone1);

        // 8. Worker withdraws payout
        vm.stopPrank();
        vm.startPrank(worker);
        uint256 workerBalanceBefore = token.balanceOf(worker);
        escrow.withdrawPayout(projectId, milestone1);
        uint256 workerBalanceAfter = token.balanceOf(worker);
        assertEq(workerBalanceAfter - workerBalanceBefore, 200 ether);

        // 9. Repeat for second milestone
        // Worker requests milestone approval
        escrow.requestMilestoneApproval(projectId, milestone2);

        // Client approves milestone
        vm.stopPrank();
        vm.startPrank(client);
        escrow.approveMilestone(projectId, milestone2);

        // Worker requests payout
        vm.stopPrank();
        vm.startPrank(worker);
        escrow.requestPayout(projectId, milestone2);

        // Client approves payout
        vm.stopPrank();
        vm.startPrank(client);
        escrow.approvePayout(projectId, milestone2);

        // Worker withdraws payout
        vm.stopPrank();
        vm.startPrank(worker);
        workerBalanceBefore = token.balanceOf(worker);
        escrow.withdrawPayout(projectId, milestone2);
        workerBalanceAfter = token.balanceOf(worker);
        assertEq(workerBalanceAfter - workerBalanceBefore, 300 ether);

        // 10. Client marks project as completed
        vm.stopPrank();
        vm.startPrank(client);
        escrow.completeProject(projectId);

        // 11. Check project status is COMPLETED
        (,,,,,,ProjectEscrow.Status status) = escrow.projects(projectId);
        assertEq(uint256(status), uint256(ProjectEscrow.Status.COMPLETED));
    }

    function testCancelProjectAndRefund() public {
        // Client creates and funds project
        vm.startPrank(client);
        escrow.createProject(projectId, worker, address(token), 500 ether);
        escrow.addMilestone(projectId, milestone1, 500 ether);
        token.approve(address(escrow), 500 ether);
        escrow.depositFunds(projectId, 500 ether);

        // Client cancels project before any approval
        escrow.cancelProject(projectId);

        // Funds should be refunded to client
        uint256 clientBalance = token.balanceOf(client);
        assertEq(clientBalance, 1000 ether);
    }

    function testRevertIfNotClientOrWorker() public {
        // Create project
        vm.startPrank(client);
        escrow.createProject(projectId, worker, address(token), 100 ether);
        escrow.addMilestone(projectId, milestone1, 100 ether);
        token.approve(address(escrow), 100 ether);
        escrow.depositFunds(projectId, 100 ether);
        vm.stopPrank();

        // Random address tries to approve milestone
        address attacker = address(0x999);
        vm.startPrank(attacker);
        vm.expectRevert(ProjectEscrow.OnlyClient.selector);
        escrow.approveMilestone(projectId, milestone1);

        // Random address tries to request payout
        vm.expectRevert(ProjectEscrow.OnlyWorker.selector);
        escrow.requestPayout(projectId, milestone1);
        vm.stopPrank();
    }
}

