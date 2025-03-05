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

// 定义 TokenDetail 类型
interface TokenDetail {
  address: string;
  symbol: string;
  decimals: number;
  available?: string; // 用户的代币余额
  receiveAmount?: string; // 赎回所得的代币数量
}

export const RedeemTabMulti = () => {
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

  const [burnAmount, setBurnAmount] = useState<bigint | null>(null);
  const [burnAmountString, setBurnAmountString] = useState<string>("0");

  // 处理用户输入的 sETF 数量
  const handleBurnAmountChange = (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const value = event.target.value;
    setBurnAmountString(value);
    setBurnAmount(value === "" ? null : BigInt(Number(value) * 1e18));
  };

  // 根据 redeemAmount 读取 redeemTokenAmounts
  const { data: redeemAmountsData, refetch: refetchGetRedeemAmounts } =
    useReadContract({
      abi: etfAbi,
      address: etfAddress,
      functionName: "getRedeemTokenAmounts",
      args: [burnAmount ?? BigInt(0)],
    });

  // 当 mintAmount 变化，重新 getInvestTokenAmounts
  useEffect(() => {
    refetchGetRedeemAmounts();
    if (
      redeemAmountsData &&
      Array.isArray(redeemAmountsData) &&
      tokens.length > 0
    ) {
      setTokens((prevTokens) =>
        prevTokens.map((token, index) => {
          const redeemAmount = redeemAmountsData[index]; // 获取对应的 payAmount
          const formattedRedeemAmount = redeemAmount
            ? (Number(redeemAmount) / Math.pow(10, token.decimals)).toFixed(8) // 根据 decimals 转换为小数，最多6位
            : "0"; // 如果没有 payAmount，设置为 "0"
          return {
            ...token,
            receiveAmount: formattedRedeemAmount,
          };
        })
      );
    }
  }, [burnAmount, redeemAmountsData, refetchGetRedeemAmounts, tokens.length]);

  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const { writeContract, isSuccess, error } = useWriteContract();
  const handleRedeem = () => {
    writeContract({
      address: etfAddress,
      abi: etfAbi,
      functionName: "redeem",
      args: [address ?? "0x", burnAmount ?? BigInt(0)],
    });
    setErrorMessage(null); // 清除错误信息
  };
  useEffect(() => {
    if (isSuccess) {
      alert("Redeem successful!"); // 弹出提示
      refetchEtfBalance();
    } else if (error) {
      setErrorMessage("Redeem failed, check your available sETF or your gas.");
    }
  }, [error, isSuccess, refetchEtfBalance]);

  return (
    <div className="tab">
      <div className="form-group">
        <div className="label-container">
          <label className="form-label">You pay</label>
          <div className="available">Available: {etfAvailable}</div>
        </div>
        <div className="input-container">
          <input
            type="number"
            placeholder="0"
            value={burnAmountString}
            onChange={handleBurnAmountChange}
          />
          <span className="token">sETF</span>
        </div>
      </div>
      <div className="arrow">&#x2193;</div>
      {/* 显示 tokens */}
      {tokens &&
        tokens.map((token, index) => {
          return (
            <div className="form-group" key={index}>
              <div className="label-container">
                <label className="form-label">You receive</label>
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
                  value={token.receiveAmount || "0"}
                  readOnly
                />
                <span className="token">{token.symbol}</span>
              </div>
            </div>
          );
        })}
      {/* 显示错误信息 */}
      {errorMessage && <div className="error-message">{errorMessage}</div>}
      <button
        className={`button ${
          !etfAvailable || parseFloat(etfAvailable) <= 0 ? "disabled" : ""
        }`}
        disabled={!etfAvailable || parseFloat(etfAvailable) <= 0}
        onClick={handleRedeem}
      >
        Redeem sETF
      </button>
    </div>
  );
};
