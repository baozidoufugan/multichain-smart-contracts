// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../../access/AdminControl.sol";
import "../interfaces/IAnycallProxy.sol";
import "../interfaces/IAnycallExecutor.sol";
import "../interfaces/IFeePool.sol";

abstract contract AppBase is AdminControl {
    //源链的代理合约
    address public callProxy;

    // associated client app on each chain
    //关联chainId -> 这条链上的anyway执行合约
    mapping(uint256 => address) public clientPeers; // key is chainId

    modifier onlyExecutor() {
        require(
            msg.sender == IAnycallProxy(callProxy).executor(),
            "AppBase: onlyExecutor"
        );
        _;
    }

    constructor(address _admin, address _callProxy) AdminControl(_admin) {
        require(_callProxy != address(0));
        callProxy = _callProxy;
    }

    receive() external payable {}

    function withdraw(address _to, uint256 _amount) external onlyAdmin {
        (bool success, ) = _to.call{value: _amount}("");
        require(success);
    }

    function setCallProxy(address _callProxy) external onlyAdmin {
        require(_callProxy != address(0));
        callProxy = _callProxy;
    }

    function setClientPeers(
        uint256[] calldata _chainIds,
        address[] calldata _peers
    ) external onlyAdmin {
        require(_chainIds.length == _peers.length);
        for (uint256 i = 0; i < _chainIds.length; i++) {
            clientPeers[_chainIds[i]] = _peers[i];
        }
    }

    //获取peer的时候,顺便校验是不是0地址
    function _getAndCheckPeer(uint256 chainId) internal view returns (address) {
        address clientPeer = clientPeers[chainId];
        require(clientPeer != address(0), "AppBase: peer not exist");
        return clientPeer;
    }

    //用来检测合约中配置的fromChainId对应的from地址是否正确。
    function _getAndCheckContext()
        internal
        view
        returns (
            address from,
            uint256 fromChainId,
            uint256 nonce
        )
    {
        //获取本链的anyExecutor地址
        address _executor = IAnycallProxy(callProxy).executor();
        //IAnycallExecutor代表了本链作为目标链时的IAnycallExecutor的地址。
        (from, fromChainId, nonce) = IAnycallExecutor(_executor).context();
        require(clientPeers[fromChainId] == from, "AppBase: wrong context");
    }

    // if the app want to support `pay fee on destination chain`,
    // we'd better wrapper the interface `IFeePool` functions here.
    //充值手续费
    function depositFee() external payable {
        //手续费池的地址？
        address _pool = IAnycallProxy(callProxy).config();
        IFeePool(_pool).deposit{value: msg.value}(address(this));
    }

    //提取手续费
    function withdrawFee(address _to, uint256 _amount) external onlyAdmin {
        address _pool = IAnycallProxy(callProxy).config();
        IFeePool(_pool).withdraw(_amount);

        (bool success, ) = _to.call{value: _amount}("");
        require(success);
    }

    function withdrawAllFee(address _pool, address _to) external onlyAdmin {
        uint256 _amount = IFeePool(_pool).executionBudget(address(this));
        IFeePool(_pool).withdraw(_amount);

        (bool success, ) = _to.call{value: _amount}("");
        require(success);
    }

    function executionBudget() external view returns (uint256) {
        address _pool = IAnycallProxy(callProxy).config();
        return IFeePool(_pool).executionBudget(address(this));
    }
}
