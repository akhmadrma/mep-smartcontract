// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

//xxx expecting huge gasfee, need more optimilization
//todo : look for reentrancy case, check all logic func
//todo : add time interval and request for extend time interval
// add  timeinterval for milestone and project
// add request extend time for worker
// add respose extend time for client

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;

contract ProjectEscrow {
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
        PENDING, // Project: pending || Milestone: pending
        ONPROGRESS, // Project: onprogress || Milestone: onprogress
        APPROVED, // Project: approved || Milestone: approved
        REJECTED, // Project: rejected || Milestone: rejected
        COMPLETED, // Project: completed || Milestone: completed
        CANCELED // Project: canceled || Milestone: canceled
    }
    // Milestone structure
    struct Milestone {
        uint256 amount;
        uint256 payoutAmount;
        ResponseStatus payoutResponse;
        ResponseStatus milestoneResponse;
        Status status;
        uint256 timestamp;
    }

    // Project structure
    struct Project {
        address worker;
        address token;
        address client;
        uint256 totalAmount;
        uint256 fundsDeposited;
        Status status;
        uint256[] milestoneIds;
        uint256 timestamp;
    }

    // Mapping for projectId
    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(uint256 => Milestone)) public projectMilestones;

    // Mapping for projectBalances
    mapping(uint256 => uint256) public projectBalances;

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
    event ProjectCreated(
        uint256 projectId,
        address client,
        address worker,
        address token
    );
    event MilestoneCreated(
        uint256 projectId,
        uint256 milestoneId,
        uint256 amount
    );
    event MilestoneAchieved(uint256 projectId, uint256 milestoneId);
    event FundsWithdrawn(uint256 projectId, uint256 amount);
    event RefundIssued(uint256 projectId, uint256 amount);
    event ProjectApproved(uint256 projectId);
    event ProjectStarted(uint256 projectId, uint256 amount);
    event MilestoneStarted(uint256 projectId, uint256 milestoneId);
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
    event PayoutWithdrawn(
        uint256 projectId,
        uint256 milestoneId,
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
    function createProject(
        uint256 _projectId,
        address _client,
        address _token
    ) public {
        if (projects[_projectId].timestamp != 0)
            revert AlreadyExists("project already exists");
        if (_client == address(0)) revert ZeroAddress("zero address");

        projects[_projectId] = Project({
            worker: msg.sender, // worker is the one who create the project
            client: _client,
            token: _token,
            totalAmount: 0,
            fundsDeposited: 0,
            status: Status.PENDING,
            timestamp: block.timestamp,
            milestoneIds: new uint256[](0)
        });
        emit ProjectCreated(
            _projectId,
            projects[_projectId].client,
            projects[_projectId].worker,
            projects[_projectId].token
        );
    }

    // Fungsi untuk menetapkan milestone untuk proyek
    function createMilestone(
        uint256 _projectId,
        uint256 _milestoneId,
        uint256 _amount
    ) external onlyWorker(_projectId) {
        if (_amount == 0) revert InvalidAmount("amount is 0");
        if (projectMilestones[_projectId][_milestoneId].timestamp != 0)
            revert AlreadyExists("milestone already exists");
        if (projects[_projectId].status != Status.PENDING)
            revert InvalidState("project is not pending");
        projectMilestones[_projectId][_milestoneId] = Milestone({
            amount: _amount,
            payoutAmount: 0,
            payoutResponse: ResponseStatus.NOT_REQUESTED,
            milestoneResponse: ResponseStatus.NOT_REQUESTED,
            status: Status.PENDING,
            timestamp: block.timestamp
        });

        projects[_projectId].totalAmount += _amount;
        projects[_projectId].milestoneIds.push(_milestoneId);
        emit MilestoneCreated(_projectId, _milestoneId, _amount);
    }

    // start project by depositing funds
    // todo add minimal deposite percentage for start project (request percentage from worker)
    function startProject(
        uint256 projectId,
        uint256 amount
    ) external onlyClient(projectId) {
        if (amount == 0) revert InvalidAmount("amount is 0");
        if (projects[projectId].status != Status.PENDING)
            revert InvalidState("project is not pending");

        IERC20 token = IERC20(projects[projectId].token);
        token.transferFrom(msg.sender, address(this), amount);

        projects[projectId].status = Status.ONPROGRESS;
        projects[projectId].fundsDeposited += amount;
        projectBalances[projectId] += amount;
        emit ProjectStarted(projectId, amount);
    }

    //start milestone
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
        emit MilestoneStarted(projectId, milestoneId);
    }

    // deposit funds from client to smart contract
    function depositFunds(
        uint256 projectId,
        uint256 amount
    ) external onlyClient(projectId) {
        if (amount == 0) revert InvalidAmount("amount is 0");
        if (amount > projects[projectId].totalAmount)
            revert InvalidAmount("amount is more than project total amount");

        IERC20 token = IERC20(projects[projectId].token);
        token.transferFrom(msg.sender, address(this), amount);

        projects[projectId].fundsDeposited += amount;
        projectBalances[projectId] += amount;
        emit FundsDeposited(projectId, amount);
    }

    //request payout for milestone needs
    function requestPayout(
        uint256 projectId,
        uint256 milestoneId,
        uint256 amount
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.status != Status.ONPROGRESS)
            revert InvalidState("milestone is not onprogress");
        if (m.payoutResponse != ResponseStatus.NOT_REQUESTED)
            revert InvalidState("payout already requested");
        if (amount == 0 || amount > m.amount)
            revert InvalidAmount("amount is 0 or more than milestone amount");
        m.payoutResponse = ResponseStatus.PENDING;
        m.payoutAmount = amount;

        emit PayoutRequested(projectId, milestoneId, amount);
    }

    //response payout for milestone needs
    function responsePayout(
        uint256 projectId,
        uint256 milestoneId,
        ResponseStatus response
    ) external onlyClient(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.payoutResponse != ResponseStatus.PENDING)
            revert InvalidState("payout is not pending");
        m.payoutResponse = response;
        emit PayoutResponse(projectId, milestoneId, response, m.payoutAmount);
    }

    //payout function for milestones needs
    function receivePayout(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.amount == 0) revert InvalidState("milestone amount is 0");
        if (m.payoutResponse != ResponseStatus.APPROVED)
            revert InvalidState("payout is not approved");

        uint256 amountToWithdraw = m.payoutAmount;
        if (projectBalances[projectId] < amountToWithdraw)
            revert InvalidState(
                "project balance is less than amount to withdraw"
            );

        // Effects
        projectBalances[projectId] -= amountToWithdraw;
        m.amount -= amountToWithdraw;
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

        emit ApprovalMilestoneRequested(projectId, milestoneId, m.status);
    }

    //response milestone approval
    function responseMilestoneApproval(
        uint256 projectId,
        uint256 milestoneId,
        ResponseStatus response
    ) external onlyClient(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.milestoneResponse != ResponseStatus.PENDING)
            revert InvalidState("milestone approval must be pending");
        m.milestoneResponse = response;
        if (response == ResponseStatus.APPROVED) m.status = Status.APPROVED;
        else if (response == ResponseStatus.REJECTED)
            m.status = Status.REJECTED;

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
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (
            m.status != Status.APPROVED &&
            m.milestoneResponse != ResponseStatus.APPROVED
        )
            revert InvalidState(
                "milestone is not approved or milestone approval is not approved"
            );

        uint256 amountToWithdraw = m.amount;
        if (projectBalances[projectId] < amountToWithdraw)
            revert InvalidState(
                "project balance is less than amount to withdraw"
            );

        projectBalances[projectId] -= amountToWithdraw;

        IERC20 token = IERC20(projects[projectId].token);
        token.safeTransfer(projects[projectId].worker, amountToWithdraw);
        m.status = Status.COMPLETED;

        emit MilestoneFundWithdrawn(projectId, milestoneId, amountToWithdraw);
    }
    event MilestoneFundWithdrawn(
        uint256 projectId,
        uint256 milestoneId,
        uint256 amount
    );

    // Fungsi untuk mengembalikan dana ke client jika milestone tidak tercapai dalam waktu yang ditentukan
    function issueRefund(uint256 projectId) external onlyClient(projectId) {
        Project storage p = projects[projectId];
        if (p.status == Status.COMPLETED)
            revert InvalidState("project is completed");

        uint256 refundable = projectBalances[projectId]; // sementara: jika lanjut, hitung dari fundsDeposited - released
        if (refundable == 0) revert InvalidAmount("refundable is 0");

        IERC20 token = IERC20(projects[projectId].token);
        token.safeTransfer(p.client, refundable);
        projectBalances[projectId] = 0;

        emit RefundIssued(projectId, refundable);
    }

    // Fungsi untuk menyelesaikan proyek dan mengonfirmasi bahwa semua dana telah diproses
    function completeProject(
        uint256 projectId
    ) external onlyWorker(projectId) {
        if (projectBalances[projectId] > 0)
            revert InvalidState("project balance is more than 0");

        Project storage p = projects[projectId];
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

    // Fungsi untuk mengambil status proyek
    function getProjectStatus(
        uint256 projectId
    ) public view returns (Status, uint256, uint256) {
        Project storage project = projects[projectId];
        return (project.status, project.fundsDeposited, project.totalAmount);
    }

    // Fungsi untuk mengambil status milestone
    function getMilestoneStatus(
        uint256 projectId,
        uint256 milestoneId
    ) public view returns (Status, uint256, uint256) {
        Milestone storage milestone = projectMilestones[projectId][milestoneId];
        return (milestone.status, milestone.amount, milestone.timestamp);
    }
}
