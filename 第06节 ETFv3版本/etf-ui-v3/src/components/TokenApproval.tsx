import { useEffect } from "react";
import { erc20Abi } from "../abis/erc20";
import { etfAddress } from "./Constants";
import { TokenDetail } from "./InvestTabMulti";
import { useSimulateContract, useWriteContract } from "wagmi";

interface TokenApprovalProps {
  token: TokenDetail;
  onApproved: () => void;
}

export const TokenApproval: React.FC<TokenApprovalProps> = ({
  token,
  onApproved,
}) => {
  const { data } = useSimulateContract({
    address: token.address as `0x${string}`,
    abi: erc20Abi,
    functionName: "approve",
    args: [
      etfAddress,
      BigInt(
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      ),
    ],
  });
  const { writeContract, isPending, isSuccess } = useWriteContract({});
  useEffect(() => {
    if (isSuccess) onApproved();
  }, [isSuccess, onApproved]);

  return (
    <button
      onClick={() => data?.request && writeContract(data.request)}
      disabled={!data?.request}
    >
      {isPending ? `Approving ${token.symbol}...` : `Approve ${token.symbol}`}
    </button>
  );
};
