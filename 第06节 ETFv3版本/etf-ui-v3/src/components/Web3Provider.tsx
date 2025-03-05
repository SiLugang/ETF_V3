import "@rainbow-me/rainbowkit/styles.css";
import {
  getDefaultConfig,
  RainbowKitProvider,
  ConnectButton,
} from "@rainbow-me/rainbowkit";
import { WagmiProvider, http } from "wagmi";
import { sepolia } from "wagmi/chains";
import { QueryClientProvider, QueryClient } from "@tanstack/react-query";
import { InfoPanel } from "./InfoPanel";
import { InvestRedeemTabs } from "./InvestRedeemTabs";

const config = getDefaultConfig({
  appName: "BlockETF",
  projectId: "5389107099f8225b488f2fc473658a62",
  chains: [sepolia],
  ssr: true, // If your dApp uses server side rendering (SSR)
  transports: {
    [sepolia.id]: http(
      "https://eth-sepolia.g.alchemy.com/v2/kGFeN--CkJ791I8qeNEeRHAdb0gBbq8z"
    ),
  },
});

const queryClient = new QueryClient();

export const Web3Provider = () => {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          <div className="app-container">
            <header className="navbar">
              <div className="navbar-logo">
                <h1>BlockETF</h1>
              </div>
              <ConnectButton />
            </header>
            <div className="main-content">
              <div className="left-panel">
                <InfoPanel />
              </div>
              <div className="right-panel">
                <InvestRedeemTabs />
              </div>
            </div>
          </div>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
};
