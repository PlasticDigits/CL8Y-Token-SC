// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

interface IGuardExecutor {
    function execute(address target, bytes calldata data) external payable returns (bytes memory);
}
