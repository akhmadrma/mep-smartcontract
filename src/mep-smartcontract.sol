// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
//xxxxxxxxx MEP-SMARTCONTRACT BETA 0.1 xxxxxxxxx

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ProjectEscrow is ReentrancyGuard {
    error OnlyClient(string message);
    error OnlyWorker(string message);
    error InvalidState(string message);
    error InvalidAmount(string message);
    error ZeroAddress(string message);
    error TransferFailed(string message);
    error AlreadyExists(string message);
    error InvalidResponseStatus(string message);

    enum ResponseStatus {
        NOT_REQUESTED,
        PENDING,
        APPROVED,
        REJECTED
    }

    enum Status {
        PENDING,
        ONPROGRESS,
        APPROVED,
        REJECTED,
        COMPLETED,
        CANCELED
    }

    // Milestone Balance structure
    struct MilestoneBalance {
        uint256 amount;
        uint256 withdrawnAmount;
    }

    // Milestone structure
    struct Milestone {
        uint256 deadline;
        uint256 payoutAmount;
        ResponseStatus payoutResponse;
        ResponseStatus milestoneResponse;
        Status status;
        uint256 responseTimestamp;
        uint256 timestamp;
    }

    // Project structure
    struct Project {
        address worker;
        address token;
        address client;
        Status status;
        uint256[] milestoneIds;
        uint256 responseTimestamp;
        uint256 timestamp;
    }

    // Project Balance Structure
    struct ProjectBalance {
        uint256 minDeposite;
        uint256 totalAmount;
        uint256 withdrawnAmount;
        uint256 fundsDeposited;
    }

    //Canceled project structure
    struct CanceledProject {
        address requestBy;
        address responseBy;
        ResponseStatus response;
        uint256 timestamp;
    }

    //Extend deadline structure
    struct ExtendDeadline {
        uint256 extendTime;
        ResponseStatus response;
        uint256 timestamp;
    }

    // Mapping for projectId
    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(uint256 => Milestone)) public projectMilestones;

    // Mapping for canceled projectId
    mapping(uint256 => CanceledProject) public canceledProjects;

    // Mapping for projectBalances
    mapping(uint256 => ProjectBalance) public projectBalances;

    // Mapping for MilestoneBalance
    mapping(uint256 => mapping(uint256 => MilestoneBalance))
        public milestoneBalances;

    // Mapping for extend deadline
    mapping(uint256 => mapping(uint256 => ExtendDeadline))
        public extendDeadlines;

    modifier onlyClient(uint256 projectId) {
        if (msg.sender != projects[projectId].client)
            revert OnlyClient("only client can call this function");
        _;
    }
    modifier onlyWorker(uint256 projectId) {
        if (msg.sender != projects[projectId].worker)
            revert OnlyWorker("only worker can call this function");
        _;
    }

    // Event function log

    event MilestoneAchieved(uint256 projectId, uint256 milestoneId);
    event FundsWithdrawn(uint256 projectId, uint256 amount);
    event RefundIssued(uint256 projectId, uint256 amount);
    event ProjectApproved(uint256 projectId);
    event FundsDeposited(uint256 projectId, uint256 amount);
    event PayoutRequested(
        uint256 projectId,
        uint256 milestoneId,
        uint256 amount
    );
    event PayoutResponse(
        uint256 projectId,
        uint256 milestoneId,
        ResponseStatus response,
        uint256 amount
    );

    event ApprovalMilestoneRequested(
        uint256 projectId,
        uint256 milestoneId,
        Status status
    );
    event MilestoneApprovalResponse(
        uint256 projectId,
        uint256 milestoneId,
        ResponseStatus response,
        Status status
    );
    event MilestoneCompleted(uint256 projectId, uint256 milestoneId);
    // Fungsi untuk membuat proyek baru
    event ProjectCreated(
        uint256 projectId,
        address client,
        address worker,
        uint minDeposite,
        address token
    );
    function createProject(
        uint256 _projectId,
        address _client,
        uint256 _minDeposite,
        address _token
    ) public {
        if (projects[_projectId].timestamp != 0)
            revert AlreadyExists("project already exists");
        if (_client == address(0)) revert ZeroAddress("zero address");
        if (_token == address(0)) revert ZeroAddress("token address is zero");
        if (_minDeposite > 70)
            revert InvalidAmount("minDeposite cannot exceed 70%");

        projects[_projectId] = Project({
            worker: msg.sender, // worker is the one who create the project
            client: _client,
            token: _token,
            status: Status.PENDING,
            responseTimestamp: 0,
            timestamp: block.timestamp,
            milestoneIds: new uint256[](0)
        });

        projectBalances[_projectId] = ProjectBalance({
            minDeposite: _minDeposite,
            totalAmount: 0,
            withdrawnAmount: 0,
            fundsDeposited: 0
        });
        emit ProjectCreated(
            _projectId,
            projects[_projectId].client,
            projects[_projectId].worker,
            projectBalances[_projectId].minDeposite,
            projects[_projectId].token
        );
    }

    // Fungsi untuk menetapkan milestone untuk proyek
    event MilestoneCreated(
        uint256 projectId,
        uint256 milestoneId,
        uint256 amount,
        uint256 deadline
    );
    function createMilestone(
        uint256 _projectId,
        uint256 _milestoneId,
        uint256 _amount,
        uint256 _deadline
    ) external onlyWorker(_projectId) {
        Milestone storage m = projectMilestones[_projectId][_milestoneId];
        Project storage p = projects[_projectId];
        ProjectBalance storage pb = projectBalances[_projectId];
        MilestoneBalance storage mb = milestoneBalances[_projectId][
            _milestoneId
        ];
        if (_amount == 0) revert InvalidAmount("amount is 0");
        if (m.timestamp != 0) revert AlreadyExists("milestone already exists");
        if (p.status != Status.PENDING)
            revert InvalidState("project is not pending");
        projectMilestones[_projectId][_milestoneId] = Milestone({
            payoutAmount: 0,
            deadline: _deadline,
            payoutResponse: ResponseStatus.NOT_REQUESTED,
            milestoneResponse: ResponseStatus.NOT_REQUESTED,
            status: Status.PENDING,
            timestamp: block.timestamp,
            responseTimestamp: 0
        });

        milestoneBalances[_projectId][_milestoneId] = MilestoneBalance({
            amount: _amount,
            withdrawnAmount: 0
        });

        pb.totalAmount += _amount;
        mb.amount = _amount;
        p.milestoneIds.push(_milestoneId);
        emit MilestoneCreated(_projectId, _milestoneId, mb.amount, m.deadline);
    }

    // start project by depositing funds
    event ProjectStarted(uint256 projectId, uint256 amount);
    function startProject(
        uint256 projectId,
        uint256 amount
    ) external onlyClient(projectId) {
        Project storage p = projects[projectId];
        ProjectBalance storage pb = projectBalances[projectId];
        IERC20 token = IERC20(p.token);
        if (token.balanceOf(msg.sender) < amount)
            revert InvalidAmount("insufficient token balance");
        if (token.allowance(msg.sender, address(this)) < amount)
            revert InvalidAmount("insufficient token allowance");
        if (amount == 0) revert InvalidAmount("amount is 0");
        if (pb.totalAmount == 0)
            revert InvalidState("no milestones created yet");
        if (amount < (pb.minDeposite * pb.totalAmount) / 100)
            revert InvalidAmount("amount is less than min deposite");
        if (amount > pb.totalAmount)
            revert InvalidAmount("amount is more than total amount");
        if (p.status != Status.PENDING)
            revert InvalidState("project is not pending");

        try token.transferFrom(msg.sender, address(this), amount) returns (
            bool success
        ) {
            if (!success) revert TransferFailed("token transfer failed");
        } catch {
            revert TransferFailed("token transfer reverted");
        }

        p.status = Status.ONPROGRESS;
        p.timestamp = block.timestamp;
        p.responseTimestamp = block.timestamp;
        pb.fundsDeposited += amount;
        emit ProjectStarted(projectId, amount);
    }

    //start milestone
    event MilestoneStarted(uint256 projectId, uint256 milestoneId);
    function startMilestone(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (
            (m.status != Status.PENDING && m.status != Status.REJECTED) ||
            projects[projectId].status != Status.ONPROGRESS
        )
            revert InvalidState(
                "milestone is not pending or rejected or project is not onprogress"
            );
        m.status = Status.ONPROGRESS;
        m.timestamp = block.timestamp;
        projects[projectId].responseTimestamp = 0;
        emit MilestoneStarted(projectId, milestoneId);
    }

    // deposit funds from client to smart contract
    function depositFunds(
        uint256 projectId,
        uint256 amount
    ) external onlyClient(projectId) {
        Project storage p = projects[projectId];
        ProjectBalance storage pb = projectBalances[projectId];
        IERC20 token = IERC20(p.token);
        if (token.balanceOf(msg.sender) < amount)
            revert InvalidAmount("insufficient token balance");
        if (token.allowance(msg.sender, address(this)) < amount)
            revert InvalidAmount("insufficient token allowance");
        if (amount == 0) revert InvalidAmount("amount is 0");
        uint256 remainingAmount = pb.totalAmount - pb.fundsDeposited;
        if (amount > remainingAmount)
            revert InvalidAmount("amount is more than remaining amount");

        try token.transferFrom(msg.sender, address(this), amount) returns (
            bool success
        ) {
            if (!success) revert TransferFailed("token transfer failed");
        } catch {
            revert TransferFailed("token transfer reverted");
        }

        pb.fundsDeposited += amount;
        emit FundsDeposited(projectId, amount);
    }

    //request payout for milestone needs
    function requestPayout(
        uint256 projectId,
        uint256 milestoneId,
        uint256 amount
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        MilestoneBalance storage mb = milestoneBalances[projectId][milestoneId];
        if (m.status != Status.ONPROGRESS)
            revert InvalidState("milestone is not onprogress");
        if (m.payoutResponse != ResponseStatus.NOT_REQUESTED)
            revert InvalidState("payout already requested");
        uint256 remainingAmount = mb.amount - mb.withdrawnAmount;
        if (amount == 0 || amount > remainingAmount)
            revert InvalidAmount(
                "amount is 0 or more than remaining milestone amount"
            );
        m.payoutResponse = ResponseStatus.PENDING;
        m.payoutAmount = amount;

        emit PayoutRequested(projectId, milestoneId, amount);
    }

    //response payout for milestone needs
    function responsePayout(
        uint256 projectId,
        uint256 milestoneId,
        ResponseStatus response
    ) external onlyClient(projectId) nonReentrant {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.payoutResponse != ResponseStatus.PENDING)
            revert InvalidState("payout is not pending");
        m.payoutResponse = response;
        emit PayoutResponse(projectId, milestoneId, response, m.payoutAmount);
    }

    //payout function for milestones needs
    event PayoutWithdrawn(
        uint256 projectId,
        uint256 milestoneId,
        uint256 amount
    );
    function receivePayout(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyWorker(projectId) nonReentrant {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        MilestoneBalance storage mb = milestoneBalances[projectId][milestoneId];
        if (mb.amount == 0) revert InvalidState("milestone balance is 0");
        if (m.payoutResponse != ResponseStatus.APPROVED)
            revert InvalidState("payout is not approved");

        uint256 amountToWithdraw = m.payoutAmount;
        uint256 remainingAmount = mb.amount - mb.withdrawnAmount;
        if (remainingAmount < amountToWithdraw)
            revert InvalidState(
                "milestone balance is less than amount to withdraw"
            );

        // Effects
        mb.withdrawnAmount += amountToWithdraw;
        projectBalances[projectId].withdrawnAmount += amountToWithdraw;
        m.payoutResponse = ResponseStatus.NOT_REQUESTED;
        m.payoutAmount = 0;

        // Interactions
        IERC20 token = IERC20(projects[projectId].token);
        token.safeTransfer(projects[projectId].worker, amountToWithdraw);

        emit PayoutWithdrawn(projectId, milestoneId, amountToWithdraw);
    }

    // func req approval milestone
    function requestApprovalMilestone(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.status != Status.ONPROGRESS)
            revert InvalidState("milestone is not onprogress");
        if (m.milestoneResponse == ResponseStatus.PENDING)
            revert InvalidState("milestone already requestded");
        m.milestoneResponse = ResponseStatus.PENDING;
        m.payoutAmount = 0;
        m.payoutResponse = ResponseStatus.NOT_REQUESTED;
        m.responseTimestamp = block.timestamp;

        emit ApprovalMilestoneRequested(projectId, milestoneId, m.status);
    }

    //response milestone approval
    function responseMilestoneApproval(
        uint256 projectId,
        uint256 milestoneId,
        ResponseStatus response
    ) external onlyClient(projectId) nonReentrant {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.milestoneResponse != ResponseStatus.PENDING)
            revert InvalidState("milestone approval must be pending");
        m.milestoneResponse = response;
        if (response == ResponseStatus.APPROVED) m.status = Status.APPROVED;
        else if (response == ResponseStatus.REJECTED)
            m.status = Status.REJECTED;
        m.responseTimestamp = 0;
        emit MilestoneApprovalResponse(
            projectId,
            milestoneId,
            response,
            m.status
        );
    }

    //func withdraw milestone fund
    function withdrawMilestoneFund(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyWorker(projectId) nonReentrant {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        MilestoneBalance storage mb = milestoneBalances[projectId][milestoneId];
        ProjectBalance storage pb = projectBalances[projectId];
        uint256 amountToWithdraw = mb.amount - mb.withdrawnAmount;
        uint256 remainingAmount = pb.fundsDeposited - pb.withdrawnAmount;
        if (
            m.status != Status.APPROVED &&
            m.milestoneResponse != ResponseStatus.APPROVED
        )
            revert InvalidState(
                "milestone is not approved or milestone approval is not approved"
            );

        if (remainingAmount < amountToWithdraw)
            revert InvalidState(
                "project funds deposited is less than amount to withdraw"
            );
        if (amountToWithdraw == 0) revert InvalidAmount("no funds to withdraw");

        pb.withdrawnAmount += amountToWithdraw;
        mb.withdrawnAmount += amountToWithdraw;
        IERC20 token = IERC20(projects[projectId].token);
        token.safeTransfer(projects[projectId].worker, amountToWithdraw);
        m.status = Status.COMPLETED;
        projects[projectId].responseTimestamp = block.timestamp;

        emit MilestoneFundWithdrawn(projectId, milestoneId, amountToWithdraw);
    }
    event MilestoneFundWithdrawn(
        uint256 projectId,
        uint256 milestoneId,
        uint256 amount
    );

    // func req cancel project
    event requestCanceledProject(
        uint256 projectId,
        address requestedBy,
        ResponseStatus response
    );
    function requestCancelProject(uint256 projectId) external {
        if (projects[projectId].status != Status.ONPROGRESS)
            revert InvalidState("project is not onprogress");
        if (msg.sender != projects[projectId].client && msg.sender != projects[projectId].worker)
        revert InvalidState("only client or worker can request cancel");
        projects[projectId].status = Status.PENDING;
        canceledProjects[projectId] = CanceledProject({
            requestBy: msg.sender, 
            responseBy: msg.sender == projects[projectId].client
                ? projects[projectId].worker
                : projects[projectId].client,
            response: ResponseStatus.PENDING,
            timestamp: block.timestamp
        });
        emit requestCanceledProject(
            projectId,
            canceledProjects[projectId].requestBy,
            ResponseStatus.PENDING
        );
    }

    // func res cancel project
    event responseCanceledProject(
        uint256 projectId,
        address canceledBy,
        address responseBy,
        ResponseStatus response
    );
    function responseCancelProject(
        uint256 projectId,
        ResponseStatus response
    ) external nonReentrant {
        if (projects[projectId].status != Status.PENDING)
            revert InvalidState("project is not pending");
        if (canceledProjects[projectId].response != ResponseStatus.PENDING)
            revert InvalidState("project is not pending");
        if (canceledProjects[projectId].responseBy != msg.sender)
            revert InvalidState("you cant response your own request");

        if (response == ResponseStatus.APPROVED) {
            ProjectBalance storage pb = projectBalances[projectId];
            projects[projectId].status = Status.CANCELED;
            canceledProjects[projectId].response = response;

            uint256 refundable = pb.fundsDeposited - pb.withdrawnAmount;
            if (refundable == 0) revert InvalidAmount("refundable is 0");
            IERC20 token = IERC20(projects[projectId].token);
            token.safeTransfer(projects[projectId].client, refundable);
        } else {
            projects[projectId].status = Status.ONPROGRESS;
        }
        emit responseCanceledProject(
            projectId,
            canceledProjects[projectId].requestBy,
            canceledProjects[projectId].responseBy,
            response
        );
    }

    // func req extend deadline
    event extendDeadlineRequested(
        uint256 projectId,
        uint256 milestoneId,
        uint256 newDeadline
    );
    function requestExtendDeadline(
        uint256 projectId,
        uint256 milestoneId,
        uint256 _extendTime
    ) external onlyWorker(projectId) nonReentrant {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.status != Status.ONPROGRESS)
            revert InvalidState("milestone is not onprogress");
        if (_extendTime == 0) revert InvalidAmount("extend time is 0");
        if (
            extendDeadlines[projectId][milestoneId].response !=
            ResponseStatus.NOT_REQUESTED
        ) revert InvalidState("extend deadline already requested");
        extendDeadlines[projectId][milestoneId] = ExtendDeadline({
            extendTime: _extendTime,
            response: ResponseStatus.PENDING,
            timestamp: block.timestamp
        });
        emit extendDeadlineRequested(projectId, milestoneId, _extendTime);
    }

    // func res extend deadline
    event extendDeadlineResponse(
        uint256 projectId,
        uint256 milestoneId,
        ResponseStatus response
    );
    function responseExtendDeadline(
        uint256 projectId,
        uint256 milestoneId,
        ResponseStatus response
    ) external onlyClient(projectId) nonReentrant {
        ExtendDeadline storage ed = extendDeadlines[projectId][milestoneId];
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (ed.response != ResponseStatus.PENDING)
            revert InvalidState("extend deadline is not pending");
        ed.response = response;
        m.deadline = response == ResponseStatus.APPROVED
            ? m.deadline + ed.extendTime
            : m.deadline;
        ed.response = ResponseStatus.NOT_REQUESTED;
        ed.extendTime = 0;
        emit extendDeadlineResponse(projectId, milestoneId, response);
    }

    // func issueRefund for client if project abandoned
    function issueRefund(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyClient(projectId) {
        Project storage p = projects[projectId];
        ProjectBalance storage pb = projectBalances[projectId];
        Milestone storage m = projectMilestones[projectId][milestoneId];
        uint256 timeDifference = m.timestamp + m.deadline - block.timestamp;

        if (p.status != Status.ONPROGRESS)
            revert InvalidState("project is not onprogress");
        if (m.status != Status.ONPROGRESS)
            revert InvalidState("milestone is not onprogress");
        if (timeDifference > 1 days)
            revert InvalidState("milestone deadline is not reached");
        uint256 refundable = pb.fundsDeposited - pb.withdrawnAmount;
        if (refundable == 0) revert InvalidAmount("refundable is 0");

        IERC20 token = IERC20(projects[projectId].token);
        token.safeTransfer(p.client, refundable);
        p.status = Status.CANCELED;

        emit RefundIssued(projectId, refundable);
    }

    // func complete project
    function completeProject(uint256 projectId) external onlyWorker(projectId) {
        Project storage p = projects[projectId];
        ProjectBalance storage pb = projectBalances[projectId];

        // Cek apakah semua milestone sudah completed
        for (uint256 i = 0; i < p.milestoneIds.length; i++) {
            if (
                projectMilestones[projectId][p.milestoneIds[i]].status !=
                Status.COMPLETED
            ) revert InvalidState("milestone is not completed");
            if (
                projectMilestones[projectId][p.milestoneIds[i]]
                    .milestoneResponse != ResponseStatus.APPROVED
            ) revert InvalidState("milestone approval is not approved");
        }

        // Cek apakah semua funds sudah withdrawn
        if (pb.withdrawnAmount != pb.fundsDeposited)
            revert InvalidState("funds not fully withdrawn");

        projects[projectId].status = Status.COMPLETED;
    }

    function getProjectDetails(
        uint256 projectId
    ) public view returns (Project memory) {
        return projects[projectId];
    }

    function getMilestoneDetails(
        uint256 projectId,
        uint256 milestoneId
    ) public view returns (Milestone memory) {
        return projectMilestones[projectId][milestoneId];
    }

    function getProjectBalance(
        uint256 projectId
    ) public view returns (ProjectBalance memory) {
        return projectBalances[projectId];
    }

    function getMilestoneBalance(
        uint256 projectId,
        uint256 milestoneId
    ) public view returns (MilestoneBalance memory) {
        return milestoneBalances[projectId][milestoneId];
    }

    function getCanceledProject(
        uint256 projectId
    ) public view returns (CanceledProject memory) {
        return canceledProjects[projectId];
    }

    function getExtendDeadline(
        uint256 projectId,
        uint256 milestoneId
    ) public view returns (ExtendDeadline memory) {
        return extendDeadlines[projectId][milestoneId];
    }
}
