// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

//xxx expecting huge gasfee, need more optimilization
//todo : look for reentrancy case, check all logic func
// todo : testing conf



import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;

contract ProjectEscrow {
    error OnlyClient();
    error OnlyWorker();
    error InvalidState();
    error InvalidAmount();
    error ZeroAddress();
    error TransferFailed();
    error AlreadyExists();

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
        bool payoutApproved;
        bool payoutRequested;
        bool milestoneApproved;
        bool milestoneApproveRequest;
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
        uint256 released; // total yang sudah dibayarkan keluar
        Status status;
        uint256 timestamp;
    }

    // Mapping for projectId
    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(uint256 => Milestone)) public projectMilestones;

    // Mapping for projectBalances
    mapping(uint256 => uint256) public projectBalances;

    modifier onlyClient(uint256 projectId) {
        if (msg.sender != projects[projectId].client) revert OnlyClient();
        _;
    }
    modifier onlyWorker(uint256 projectId) {
        if (msg.sender != projects[projectId].worker) revert OnlyWorker();
        _;
    }

    // Event function log
    event ProjectCreated(
        uint256 projectId,
        address client,
        address worker,
        address token,
        Status status
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
    event PayoutApproved(uint256 projectId, uint256 milestoneId);
    event PayoutRejected(uint256 projectId, uint256 milestoneId);
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
    event MilestoneApproved(uint256 projectId, uint256 milestoneId);
    event MilestoneRejected(uint256 projectId, uint256 milestoneId);
    event MilestoneCompleted(uint256 projectId, uint256 milestoneId);
    event MilestoneCancelled(uint256 projectId, uint256 milestoneId);
    event MilestoneFailed(uint256 projectId, uint256 milestoneId);
    event MilestonePaused(uint256 projectId, uint256 milestoneId);
    // Fungsi untuk membuat proyek baru
    function createProject(
        uint256 _projectId,
        address _client,
        address _token
    ) public {
        if (projects[_projectId].timestamp != 0) revert AlreadyExists();
        if (_client == address(0)) revert ZeroAddress();

        projects[_projectId] = Project({
            worker: msg.sender, // worker is the one who create the project
            client: _client,
            token: _token,
            totalAmount: 0,
            fundsDeposited: 0,
            released: 0,
            status: Status.PENDING,
            timestamp : block.timestamp
        });
        emit ProjectCreated(
            _projectId,
            projects[_projectId].client,
            projects[_projectId].worker,
            projects[_projectId].token,
            projects[_projectId].status
        );
    }

    // Fungsi untuk menetapkan milestone untuk proyek
    function createMilestone(
        uint256 _projectId,
        uint256 _milestoneId,
        uint256 _amount
    ) external onlyWorker(_projectId) {
        if (_amount == 0) revert InvalidAmount();
        if (projectMilestones[_projectId][_milestoneId].timestamp != 0) revert AlreadyExists();
        if (projects[_projectId].status != Status.PENDING) revert InvalidState();
        projectMilestones[_projectId][_milestoneId] = Milestone({
            amount: _amount,
            payoutAmount: 0,
            payoutApproved: false,
            payoutRequested: false,
            milestoneApproved: false,
            milestoneApproveRequest: false,
            status: Status.PENDING,
            timestamp: block.timestamp
        });
        
        projects[_projectId].totalAmount += _amount;
        emit MilestoneCreated(_projectId, _milestoneId, _amount);
    }

    // start project by depositing funds
    // todo add minimal deposite percentage for start project (request percentage from worker)
    function startProject(
        uint256 projectId,
        uint256 amount
    ) external onlyClient(projectId) {
        if (amount == 0) revert InvalidAmount();
        if (projects[projectId].status != Status.PENDING) revert InvalidState();

        IERC20 token = IERC20(projects[projectId].token);
        token.transferFrom(msg.sender, address(this), amount);

        projects[projectId].status = Status.ONPROGRESS;
        projects[projectId].fundsDeposited += amount;
        projectBalances[projectId] += amount; // sementara tetap, lihat catatan di bawah
        emit ProjectStarted(projectId, amount);
    }

    //start milestone
    function startMilestone(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.status != Status.PENDING && m.status != Status.REJECTED || projects[projectId].status != Status.ONPROGRESS) revert InvalidState();
        m.status = Status.ONPROGRESS;
        emit MilestoneStarted(projectId, milestoneId);
    }

    // deposit funds from client to smart contract
    function depositFunds(
        uint256 projectId,
        uint256 amount
    ) external onlyClient(projectId) {
        if (amount == 0) revert InvalidAmount();

        IERC20 token = IERC20(projects[projectId].token);
        token.safeTransferFrom(msg.sender, address(this), amount);

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
        if (m.status != Status.ONPROGRESS) revert InvalidState();
        if (m.payoutRequested) revert InvalidState();
        if (amount == 0 || amount > m.amount) revert InvalidAmount();
        m.payoutRequested = true;
        m.payoutAmount = amount;

        emit PayoutRequested(projectId, milestoneId, amount);
    }

    //approve payout for milestone needs
    function approvePayout(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyClient(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.payoutApproved || !m.payoutRequested) revert InvalidState();
        m.payoutApproved = true;
        emit PayoutApproved(projectId, milestoneId);
    }

    //reject payout for milestone needs
    function rejectPayout(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyClient(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.payoutApproved || !m.payoutRequested) revert InvalidState();
        m.payoutApproved = false;
        m.payoutRequested = false;
        m.payoutAmount = 0;
        emit PayoutRejected(projectId, milestoneId);
    }

    //payout function for milestones needs
    function receivePayout(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.amount == 0) revert InvalidState();
        if (m.status != Status.ONPROGRESS) revert InvalidState();
        if (!m.payoutApproved) revert InvalidState();
        if (!m.payoutRequested) revert InvalidState();

        uint256 amountToWithdraw = m.payoutAmount;
        if (projectBalances[projectId] < amountToWithdraw)
            revert InvalidState();

        // Effects
        projectBalances[projectId] -= amountToWithdraw;
        projects[projectId].released += amountToWithdraw;
        m.payoutApproved = false;
        m.payoutRequested = false;
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
        if (m.status != Status.ONPROGRESS) revert InvalidState();
        m.status = Status.PENDING;
        m.milestoneApproveRequest = true;

        emit ApprovalMilestoneRequested(projectId, milestoneId, m.status);
    }

    // func approve milestone
    function approveMilestone(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyClient(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        if (m.status != Status.PENDING) revert InvalidState();
        if (!m.milestoneApproveRequest) revert InvalidState();
        m.status = Status.APPROVED;
        m.milestoneApproved = true;
        emit MilestoneApproved(projectId, milestoneId);
    }

    // func reject milestone
    function rejectMilestone(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyClient(projectId) {
        projectMilestones[projectId][milestoneId].status = Status.REJECTED;
        emit MilestoneRejected(projectId, milestoneId);
    }

    //func withdraw milestone fund
    function withdrawMilestoneFund(
        uint256 projectId,
        uint256 milestoneId
    ) external onlyWorker(projectId) {
        Milestone storage m = projectMilestones[projectId][milestoneId];
        // butuh status approved DAN flag true
        if (m.status != Status.APPROVED || !m.milestoneApproved)
            revert InvalidState();

        uint256 amountToWithdraw = m.amount;
        if (projectBalances[projectId] < amountToWithdraw)
            revert InvalidState();

        projectBalances[projectId] -= amountToWithdraw;
        projects[projectId].released += amountToWithdraw;

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
        if (p.status == Status.COMPLETED) revert InvalidState();

        uint256 refundable = projectBalances[projectId]; // sementara: jika lanjut, hitung dari fundsDeposited - released
        if (refundable == 0) revert InvalidAmount();

        projectBalances[projectId] = 0;
        p.fundsDeposited = p.released; // sisakan angka sesuai dana yg sudah keluar

        IERC20 token = IERC20(projects[projectId].token);
        token.safeTransfer(p.client, refundable);

        emit RefundIssued(projectId, refundable);
    }

    // Fungsi untuk menyelesaikan proyek dan mengonfirmasi bahwa semua dana telah diproses
    function completeProject(uint256 projectId) external onlyWorker(projectId) {
        if (projects[projectId].status != Status.ONPROGRESS) revert InvalidState();
        if (projectBalances[projectId] > 0) revert InvalidState();

        projects[projectId].status = Status.COMPLETED;
    }

    function getProjectDetails(uint256 projectId) public view returns (Project memory) {
        return projects[projectId];
    }

    function getMilestoneDetails(uint256 projectId, uint256 milestoneId) public view returns (Milestone memory) {
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
