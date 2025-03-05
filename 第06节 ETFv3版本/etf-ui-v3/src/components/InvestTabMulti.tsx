import { etfAbi } from "../abis/etf";
import { erc20Abi } from "../abis/erc20";
import { etfAddress } from "./Constants";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
} from "wagmi";
import { useEffect, useState, useMemo } from "react";
import { TokenApproval } from "./TokenApproval";

// 定义 TokenDetail 类型
export interface TokenDetail {
  address: string;
  symbol: string;
  decimals: number;
  available?: string; // 用户的代币余额
  payAmount?: string; // 投资所需的代币数量
  allowance?: bigint; // 用户对 ETF 合约的授权额度
}

export const InvestTabMulti = () => {
  const { address, isConnected } = useAccount();

  const [etfAvailable, setEtfAvailable] = useState<string>("0");

  // 读取用户的 ETF 余额
  const { data: etfBalance, refetch: refetchEtfBalance } = useReadContract({
    abi: erc20Abi,
    address: etfAddress,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
  });

  // 处理用户的 etfAvailable 数据
  useEffect(() => {
    if (isConnected && typeof etfBalance === "bigint") {
      const available = etfBalance
        ? (Number(etfBalance) / Math.pow(10, 18)).toFixed(2) // 修改为带小数的格式，最多两位
        : "0";
      setEtfAvailable(available);
    } else {
      setEtfAvailable("0");
    }
  }, [etfBalance, isConnected]);

  const [tokens, setTokens] = useState<TokenDetail[]>([]);

  // 读取 ETF 合约中的 tokens
  const { data: tokensData } = useReadContract({
    abi: etfAbi,
    address: etfAddress,
    functionName: "getTokens",
  });

  // 构建获取 symbol 和 decimals 的读取请求
  const symbolDecimalsReads = useMemo(() => {
    if (!tokensData || !Array.isArray(tokensData)) {
      return [];
    }

    const symbolCalls = tokensData.map((tokenAddress: string) => ({
      address: tokenAddress as `0x${string}`,
      abi: erc20Abi,
      functionName: "symbol",
    }));

    const decimalsCalls = tokensData.map((tokenAddress: string) => ({
      address: tokenAddress as `0x${string}`,
      abi: erc20Abi,
      functionName: "decimals",
    }));

    return [...symbolCalls, ...decimalsCalls];
  }, [tokensData]);

  // 使用 useReadContracts 获取 symbol 和 decimals
  const { data: symbolDecimalsData } = useReadContracts({
    contracts: symbolDecimalsReads,
  });

  // 构建获取 balanceOf 的读取请求，仅在连接钱包时
  const balanceReads = useMemo(() => {
    if (!tokensData || !Array.isArray(tokensData) || !isConnected || !address) {
      return [];
    }

    return tokensData.map((tokenAddress: string) => ({
      address: tokenAddress as `0x${string}`,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [address],
    }));
  }, [tokensData, isConnected, address]);

  // 使用 useContractReads 获取 balanceOf
  const { data: balanceData } = useReadContracts({
    contracts: balanceReads,
  });

  // 处理 symbol 和 decimals 数据
  useEffect(() => {
    if (
      symbolDecimalsData &&
      Array.isArray(symbolDecimalsData) &&
      tokensData &&
      Array.isArray(tokensData)
    ) {
      const tokensWithDetails: TokenDetail[] = tokensData.map(
        (tokenAddress, index) => {
          const symbol = symbolDecimalsData[index]?.result as string;
          const decimals = symbolDecimalsData[index + tokensData.length]
            ?.result as number;

          return {
            address: tokenAddress,
            symbol,
            decimals,
          };
        }
      );
      setTokens(tokensWithDetails);
    }
  }, [symbolDecimalsData, tokensData]);

  // 处理 balanceOf 数据
  useEffect(() => {
    if (
      balanceData &&
      Array.isArray(balanceData) &&
      tokensData &&
      Array.isArray(tokensData)
    ) {
      setTokens((prevTokens) =>
        prevTokens.map((token, index) => {
          const balance = balanceData[index]?.result as bigint | undefined;
          const available = balance
            ? (Number(balance) / Math.pow(10, token.decimals)).toFixed(2) // 修改为带小数的格式，最多两位
            : "0";
          return {
            ...token,
            available,
          };
        })
      );
    }
  }, [balanceData, tokensData]);

  const [mintAmount, setMintAmount] = useState<bigint | null>(null);
  const [mintAmountString, setMintAmountString] = useState<string>("0");

  // 处理用户输入的 sETF 数量
  const handleMintAmountChange = (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const value = event.target.value;
    setMintAmountString(value);
    setMintAmount(value === "" ? null : BigInt(Number(value) * 1e18));
  };

  // 根据 mintAmount 读取 investTokenAmounts
  const { data: investAmountsData, refetch: refetchGetInvestAmounts } =
    useReadContract({
      abi: etfAbi,
      address: etfAddress,
      functionName: "getInvestTokenAmounts",
      args: [mintAmount ?? BigInt(0)],
    });

  // 当 mintAmount 变化，重新 getInvestTokenAmounts
  useEffect(() => {
    refetchGetInvestAmounts();
    if (
      investAmountsData &&
      Array.isArray(investAmountsData) &&
      tokens.length > 0
    ) {
      setTokens((prevTokens) =>
        prevTokens.map((token, index) => {
          const payAmount = investAmountsData[index]; // 获取对应的 payAmount
          const formattedPayAmount = payAmount
            ? (Number(payAmount) / Math.pow(10, token.decimals)).toFixed(8) // 根据 decimals 转换为小数，最多6位
            : "0"; // 如果没有 payAmount，设置为 "0"
          return {
            ...token,
            payAmount: formattedPayAmount,
          };
        })
      );
    }
  }, [mintAmount, investAmountsData, refetchGetInvestAmounts, tokens.length]);

  // 构建获取 allowance 的读取请求，仅在连接钱包时
  const allowanceReads = useMemo(() => {
    if (!tokensData || !Array.isArray(tokensData) || !isConnected || !address) {
      return [];
    }

    return tokensData.map((tokenAddress: string) => ({
      address: tokenAddress as `0x${string}`,
      abi: erc20Abi,
      functionName: "allowance",
      args: [address, etfAddress],
    }));
  }, [tokensData, isConnected, address]);

  // 使用 useReadContracts 获取 allowances
  const { data: allowanceData } = useReadContracts({
    contracts: allowanceReads,
  });

  // 处理 allowance 数据
  useEffect(() => {
    if (
      allowanceData &&
      Array.isArray(allowanceData) &&
      tokensData &&
      Array.isArray(tokensData)
    ) {
      setTokens((prevTokens) =>
        prevTokens.map((token, index) => {
          const allowance = allowanceData[index]?.result as bigint | undefined;
          return {
            ...token,
            allowance: allowance ?? BigInt(0),
          };
        })
      );
    }
  }, [allowanceData, tokensData]);

  // 添加状态变量 approvalIndex，控制用户只能按顺序授权代币
  const [approvalIndex, setApprovalIndex] = useState(0);

  // 检查所有代币的 allowance 是否足够
  const allAllowancesSufficient = tokens.every((token) => {
    const allowanceNeeded =
      token.payAmount && token.decimals
        ? BigInt(
            Math.floor(Number(token.payAmount) * Math.pow(10, token.decimals))
          )
        : BigInt(0);
    return token.allowance && token.allowance >= allowanceNeeded;
  });

  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const { writeContract, isSuccess, error } = useWriteContract();
  const handleInvest = () => {
    if (allAllowancesSufficient) {
      writeContract({
        address: etfAddress,
        abi: etfAbi,
        functionName: "invest",
        args: [address ?? "0x", mintAmount ?? BigInt(0)],
      });
      setErrorMessage(null); // 清除错误信息
    }
  };
  useEffect(() => {
    if (isSuccess) {
      alert("Invest successful!"); // 弹出提示
      refetchEtfBalance();
    } else if (error) {
      setErrorMessage("Invest failed, check your available or your gas.");
    }
  }, [error, isSuccess, refetchEtfBalance]);

  return (
    <div className="tab">
      <div className="form-group">
        <div className="label-container">
          <label className="form-label">You receive</label>
          <div className="available">Available: {etfAvailable}</div>
        </div>
        <div className="input-container">
          <input
            type="number"
            placeholder="0"
            value={mintAmountString}
            onChange={handleMintAmountChange}
          />
          <span className="token">sETF</span>
        </div>
      </div>
      <div className="arrow">&#x2191;</div>
      {/* 显示 tokens */}
      {tokens &&
        tokens.map((token, index) => {
          const allowanceNeeded =
            token.payAmount && token.decimals
              ? BigInt(
                  Math.floor(
                    Number(token.payAmount) * Math.pow(10, token.decimals)
                  )
                )
              : BigInt(0);
          const allowanceSufficient =
            token.allowance && token.allowance >= allowanceNeeded;

          return (
            <div className="form-group" key={index}>
              <div className="label-container">
                <label className="form-label">You pay</label>
                {isConnected ? (
                  <div className="available">
                    Available: {token.available || "0"}
                  </div>
                ) : (
                  <div className="available">Available: 0</div>
                )}
              </div>
              <div className="input-container">
                <input
                  type="number"
                  placeholder="0"
                  value={token.payAmount || "0"}
                  readOnly
                />
                <span className="token">{token.symbol}</span>
              </div>
              {/* 授权按钮 */}
              {!allowanceSufficient &&
              approvalIndex === index &&
              mintAmount &&
              mintAmount > 0n ? (
                <TokenApproval
                  token={token}
                  onApproved={() => {
                    // 更新代币的 allowance
                    setTokens((prevTokens) =>
                      prevTokens.map((t, i) =>
                        i === index
                          ? {
                              ...t,
                              allowance: BigInt(
                                "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
                              ),
                            }
                          : t
                      )
                    );
                    // 允许下一个代币授权
                    setApprovalIndex(index + 1);
                  }}
                />
              ) : null}
            </div>
          );
        })}
      {/* 显示错误信息 */}
      {errorMessage && <div className="error-message">{errorMessage}</div>}
      <button
        className={`button ${!allAllowancesSufficient ? "disabled" : ""}`}
        disabled={!allAllowancesSufficient}
        onClick={handleInvest}
      >
        Invest sETF
      </button>
    </div>
  );
};
