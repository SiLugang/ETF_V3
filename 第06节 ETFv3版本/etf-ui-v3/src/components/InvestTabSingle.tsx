import { etfAbi } from "../abis/etf";
import { erc20Abi } from "../abis/erc20";
import { etfQuoterAbi } from "../abis/etfQuoter";
import {
  etfAddress,
  usdcAddress,
  wethAddress,
  etfQuoterAddress,
} from "./Constants";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useBalance,
} from "wagmi";
import { useEffect, useState, useMemo } from "react";
import { TokenApproval } from "./TokenApproval";

// 定义 TokenDetail 类型
export interface TokenDetail {
  address: string;
  symbol: string;
  decimals: number;
}

export const InvestTabSingle = () => {
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
        ? (Number(etfBalance) / Math.pow(10, 18)).toFixed(2)
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

  // 手动将 USDC 添加到代币列表中
  const tokensWithUSDC = useMemo(() => {
    if (!tokensData || !Array.isArray(tokensData)) {
      return [usdcAddress];
    }
    // 添加 USDC 和 ETH 地址到代币列表
    return [...tokensData, usdcAddress];
  }, [tokensData]);

  // 构建获取 symbol 和 decimals 的读取请求
  const symbolDecimalsReads = useMemo(() => {
    if (!tokensWithUSDC || !Array.isArray(tokensWithUSDC)) {
      return [];
    }

    const symbolCalls = tokensWithUSDC.map((tokenAddress: string) => ({
      address: tokenAddress as `0x${string}`,
      abi: erc20Abi,
      functionName: "symbol",
    }));

    const decimalsCalls = tokensWithUSDC.map((tokenAddress: string) => ({
      address: tokenAddress as `0x${string}`,
      abi: erc20Abi,
      functionName: "decimals",
    }));

    return [...symbolCalls, ...decimalsCalls];
  }, [tokensWithUSDC]);

  // 使用 useReadContracts 获取 symbol 和 decimals
  const { data: symbolDecimalsData } = useReadContracts({
    contracts: symbolDecimalsReads,
  });

  // 使用 useMemo 包装 ETH_TOKEN 的初始化
  const ETH_TOKEN = useMemo<TokenDetail>(
    () => ({
      address: wethAddress,
      symbol: "ETH",
      decimals: 18,
    }),
    []
  );

  // 处理 symbol 和 decimals 数据
  useEffect(() => {
    if (
      symbolDecimalsData &&
      Array.isArray(symbolDecimalsData) &&
      tokensWithUSDC &&
      Array.isArray(tokensWithUSDC)
    ) {
      const tokensWithDetails: TokenDetail[] = tokensWithUSDC.map(
        (tokenAddress, index) => {
          const symbol = symbolDecimalsData[index].result as string;
          const decimals = symbolDecimalsData[index + tokensWithUSDC.length]
            .result as number;

          return {
            address: tokenAddress,
            symbol,
            decimals,
          };
        }
      );
      // 将 ETH 添加到代币列表
      setTokens([...tokensWithDetails, ETH_TOKEN]);
    }
  }, [ETH_TOKEN, symbolDecimalsData, tokensWithUSDC]);

  // 单代币相关状态
  const [selectedToken, setSelectedToken] = useState<TokenDetail | null>(null);
  const [selectedTokenBalance, setSelectedTokenBalance] = useState<string>("0");
  const [selectedTokenAllowance, setSelectedTokenAllowance] = useState<bigint>(
    BigInt(0)
  );
  const [selectedTokenPayAmount, setSelectedTokenPayAmount] =
    useState<string>("0");

  // 处理代币选择
  const handleTokenSelect = (event: React.ChangeEvent<HTMLSelectElement>) => {
    const tokenAddress = event.target.value;
    const token = tokens.find((t) => t.address === tokenAddress);
    setSelectedToken(token ?? null);
  };

  // 获取代币余额
  const {
    data: selectedTokenBalanceData,
    refetch: refetchSelectedTokenBalance,
  } = useBalance({
    address: address,
    token:
      selectedToken?.address === ETH_TOKEN.address
        ? undefined
        : (selectedToken?.address as `0x${string}`),
  });

  useEffect(() => {
    if (selectedTokenBalanceData && selectedToken) {
      const balance = selectedTokenBalanceData.value as bigint;
      const available = (
        Number(balance) / Math.pow(10, selectedToken.decimals)
      ).toFixed(2);
      setSelectedTokenBalance(available);
    } else {
      setSelectedTokenBalance("0");
    }
  }, [selectedTokenBalanceData, selectedToken]);

  // 获取代币的授权额度
  const {
    data: selectedTokenAllowanceData,
    refetch: refetchSelectedTokenAllowance,
  } = useReadContract({
    abi: erc20Abi,
    address: (selectedToken?.address as `0x${string}`) ?? "0x",
    functionName: "allowance",
    args: address ? [address, etfAddress] : undefined,
  });

  useEffect(() => {
    if (selectedToken) {
      if (selectedToken.address === ETH_TOKEN.address) {
        // ETH 不需要授权
        setSelectedTokenAllowance(
          BigInt(
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
          )
        );
      } else if (selectedTokenAllowanceData) {
        const allowance = selectedTokenAllowanceData as bigint;
        setSelectedTokenAllowance(allowance);
      } else {
        setSelectedTokenAllowance(BigInt(0));
      }
    }
  }, [ETH_TOKEN.address, selectedToken, selectedTokenAllowanceData]);

  // 处理用户输入的 sETF 数量
  const [mintAmount, setMintAmount] = useState<bigint | null>(null);
  const [mintAmountString, setMintAmountString] = useState<string>("0");

  const handleMintAmountChange = (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const value = event.target.value;
    setMintAmountString(value);
    setMintAmount(value === "" ? null : BigInt(Number(value) * 1e18));
  };

  // 根据 mintAmount 获取所需的代币数量和交易路径
  const {
    data: quoteInvestWithTokenData,
    refetch: refetchQuoteInvestWithToken,
  } = useReadContract({
    abi: etfQuoterAbi,
    address: etfQuoterAddress,
    functionName: "quoteInvestWithToken",
    args: [
      etfAddress,
      (selectedToken?.address as `0x${string}`) ?? "0x",
      mintAmount ?? BigInt(0),
    ],
  });

  // 交易路径状态
  const [swapPaths, setSwapPaths] = useState<string[]>([]);

  useEffect(() => {
    console.log("quoteInvestWithTokenData:", quoteInvestWithTokenData);
    if (quoteInvestWithTokenData && selectedToken) {
      // 增加 0.5% 的滑点
      const payAmount =
        (BigInt(quoteInvestWithTokenData[0]) * BigInt(1005)) / BigInt(1000);
      const formattedPayAmount = payAmount
        ? (Number(payAmount) / Math.pow(10, selectedToken.decimals)).toFixed(8)
        : "0";
      setSelectedTokenPayAmount(formattedPayAmount);

      const paths = quoteInvestWithTokenData[1];
      setSwapPaths([...paths]);
    } else {
      setSelectedTokenPayAmount("0");
    }
  }, [quoteInvestWithTokenData, selectedToken]);

  // 当选定代币或 mintAmount 改变时，重新获取数据
  useEffect(() => {
    if (selectedToken && address) {
      refetchSelectedTokenBalance();
      refetchSelectedTokenAllowance();
      refetchQuoteInvestWithToken();
    }
  }, [
    selectedToken,
    refetchSelectedTokenBalance,
    refetchSelectedTokenAllowance,
    refetchQuoteInvestWithToken,
    address,
  ]);

  useEffect(() => {
    if (mintAmount && selectedToken) {
      refetchQuoteInvestWithToken();
    }
  }, [mintAmount, refetchQuoteInvestWithToken, selectedToken]);

  // 检查授权是否足够
  const allowanceNeeded =
    selectedTokenPayAmount && selectedToken
      ? BigInt(
          Math.floor(
            Number(selectedTokenPayAmount) *
              Math.pow(10, selectedToken.decimals)
          )
        )
      : BigInt(0);
  const allowanceSufficient =
    selectedTokenAllowance && selectedTokenAllowance >= allowanceNeeded;

  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const { writeContract, isSuccess, error } = useWriteContract();

  const handleInvest = () => {
    if (allowanceSufficient && selectedToken && mintAmount && mintAmount > 0n) {
      const maxSrcTokenAmount = BigInt(
        Number(selectedTokenPayAmount) * Math.pow(10, selectedToken.decimals)
      );
      if (selectedToken.address == ETH_TOKEN.address) {
        writeContract({
          address: etfAddress,
          abi: etfAbi,
          functionName: "investWithETH",
          args: [
            address ?? "0x",
            mintAmount,
            swapPaths as readonly `0x${string}`[],
          ],
          value: maxSrcTokenAmount,
        });
      } else {
        writeContract({
          address: etfAddress,
          abi: etfAbi,
          functionName: "investWithToken",
          args: [
            selectedToken.address as `0x${string}`,
            address as `0x${string}`,
            mintAmount,
            maxSrcTokenAmount,
            swapPaths as readonly `0x${string}`[],
          ],
        });
      }

      setErrorMessage(null); // 清除错误信息
    }
  };

  useEffect(() => {
    if (isSuccess) {
      alert("Invest successful!"); // 弹出提示
      refetchEtfBalance();
    } else if (error) {
      console.log(error);
      setErrorMessage("Invest failed, check your available balance or gas.");
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
      {/* 代币选择器 */}
      <div className="form-group">
        <div className="label-and-select">
          <label className="form-label">Select Token</label>
          <select
            className="custom-select"
            onChange={handleTokenSelect}
            value={selectedToken?.address || ""}
          >
            <option value="">Select a token</option>
            {tokens.map((token) => (
              <option key={token.address} value={token.address}>
                {token.symbol}
              </option>
            ))}
          </select>
        </div>
      </div>
      {/* 显示选定代币的信息 */}
      {selectedToken && (
        <div className="form-group">
          <div className="label-container">
            <label className="form-label">You pay</label>
            {isConnected ? (
              <div className="available">
                Available: {selectedTokenBalance || "0"}
              </div>
            ) : (
              <div className="available">Available: 0</div>
            )}
          </div>
          <div className="input-container">
            <input
              type="number"
              placeholder="0"
              value={selectedTokenPayAmount || "0"}
              readOnly
            />
            <span className="token">{selectedToken.symbol}</span>
          </div>
          {/* 授权按钮 */}
          {selectedToken?.address !== ETH_TOKEN.address &&
            !allowanceSufficient &&
            mintAmount &&
            mintAmount > 0n && (
              <TokenApproval
                token={selectedToken}
                onApproved={() => {
                  setSelectedTokenAllowance(
                    BigInt(
                      "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
                    )
                  );
                }}
              />
            )}
        </div>
      )}
      {/* 显示错误信息 */}
      {errorMessage && <div className="error-message">{errorMessage}</div>}
      <button
        className={`button ${
          !allowanceSufficient ||
          !selectedToken ||
          !mintAmount ||
          mintAmount <= 0n
            ? "disabled"
            : ""
        }`}
        disabled={
          !allowanceSufficient ||
          !selectedToken ||
          !mintAmount ||
          mintAmount <= 0n
        }
        onClick={handleInvest}
      >
        Invest sETF
      </button>
    </div>
  );
};
