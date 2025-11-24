import { BrowserRouter, Routes, Route, useLocation, useNavigate } from 'react-router-dom';
import { useEffect, lazy, Suspense } from 'react';
import { Layout } from './components/Layout';

// Lazy load routes for code splitting - reduces initial bundle size
const Home = lazy(() => import('./pages/Home').then(m => ({ default: m.Home })));
const Installation = lazy(() => import('./pages/Installation').then(m => ({ default: m.Installation })));
const Upgrading = lazy(() => import('./pages/Upgrading').then(m => ({ default: m.Upgrading })));
const Verification = lazy(() => import('./pages/Verification').then(m => ({ default: m.Verification })));
const Configuration = lazy(() => import('./pages/Configuration').then(m => ({ default: m.Configuration })));
const WebUIOverview = lazy(() => import('./pages/webui/Overview').then(m => ({ default: m.Overview })));
const WebUILogin = lazy(() => import('./pages/webui/Login').then(m => ({ default: m.Login })));
const WebUINavigation = lazy(() => import('./pages/webui/Navigation').then(m => ({ default: m.Navigation })));
const WebUIDashboard = lazy(() => import('./pages/webui/Dashboard').then(m => ({ default: m.Dashboard })));
const WebUINetwork = lazy(() => import('./pages/webui/Network').then(m => ({ default: m.Network })));
const WebUIDevices = lazy(() => import('./pages/webui/Devices').then(m => ({ default: m.Devices })));
const WebUIDeviceUsage = lazy(() => import('./pages/webui/DeviceUsage').then(m => ({ default: m.DeviceUsage })));
const WebUISystem = lazy(() => import('./pages/webui/System').then(m => ({ default: m.System })));
const WebUISpeedtest = lazy(() => import('./pages/webui/Speedtest').then(m => ({ default: m.Speedtest })));
const WebUISystemInfo = lazy(() => import('./pages/webui/SystemInfo').then(m => ({ default: m.SystemInfo })));
const WebUIApprise = lazy(() => import('./pages/webui/Apprise').then(m => ({ default: m.Apprise })));
const SystemConfig = lazy(() => import('./pages/configuration/System').then(m => ({ default: m.SystemConfig })));
const WanConfig = lazy(() => import('./pages/configuration/Wan').then(m => ({ default: m.WanConfig })));
const CakeConfig = lazy(() => import('./pages/configuration/Cake').then(m => ({ default: m.CakeConfig })));
const LanBridgesConfig = lazy(() => import('./pages/configuration/LanBridges').then(m => ({ default: m.LanBridgesConfig })));
const HomelabConfig = lazy(() => import('./pages/configuration/Homelab').then(m => ({ default: m.HomelabConfig })));
const LanConfig = lazy(() => import('./pages/configuration/Lan').then(m => ({ default: m.LanConfig })));
const PortForwardingConfig = lazy(() => import('./pages/configuration/PortForwarding').then(m => ({ default: m.PortForwardingConfig })));
const DynDnsConfig = lazy(() => import('./pages/configuration/DynDns').then(m => ({ default: m.DynDnsConfig })));
const GlobalDnsConfig = lazy(() => import('./pages/configuration/GlobalDns').then(m => ({ default: m.GlobalDnsConfig })));
const WebuiConfig = lazy(() => import('./pages/configuration/Webui').then(m => ({ default: m.WebuiConfig })));
const AppriseConfig = lazy(() => import('./pages/configuration/Apprise').then(m => ({ default: m.AppriseConfig })));

// Component to handle trailing slash redirects for GitHub Pages
function TrailingSlashHandler() {
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    // Only redirect if path has trailing slash and is not root
    if (location.pathname !== '/' && location.pathname.endsWith('/')) {
      navigate(location.pathname.slice(0, -1), { replace: true });
    }
  }, [location.pathname, navigate]);

  return null;
}

// Loading fallback component
function LoadingFallback() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="text-gray-600 dark:text-gray-400">Loading...</div>
    </div>
  );
}

function App() {
  return (
    <BrowserRouter basename={import.meta.env.VITE_BASE_PATH || '/docs/'}>
      <TrailingSlashHandler />
      <Layout>
        <Suspense fallback={<LoadingFallback />}>
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/installation" element={<Installation />} />
            <Route path="/upgrading" element={<Upgrading />} />
            <Route path="/verification" element={<Verification />} />
            <Route path="/webui" element={<WebUIOverview />} />
            <Route path="/webui/login" element={<WebUILogin />} />
            <Route path="/webui/navigation" element={<WebUINavigation />} />
            <Route path="/webui/dashboard" element={<WebUIDashboard />} />
            <Route path="/webui/network" element={<WebUINetwork />} />
            <Route path="/webui/devices" element={<WebUIDevices />} />
            <Route path="/webui/device-usage" element={<WebUIDeviceUsage />} />
            <Route path="/webui/system" element={<WebUISystem />} />
            <Route path="/webui/speedtest" element={<WebUISpeedtest />} />
            <Route path="/webui/system-info" element={<WebUISystemInfo />} />
            <Route path="/webui/apprise" element={<WebUIApprise />} />
            <Route path="/configuration" element={<Configuration />} />
            <Route path="/configuration/system" element={<SystemConfig />} />
            <Route path="/configuration/wan" element={<WanConfig />} />
            <Route path="/configuration/cake" element={<CakeConfig />} />
            <Route path="/configuration/lan-bridges" element={<LanBridgesConfig />} />
            <Route path="/configuration/homelab" element={<HomelabConfig />} />
            <Route path="/configuration/lan" element={<LanConfig />} />
            <Route path="/configuration/port-forwarding" element={<PortForwardingConfig />} />
            <Route path="/configuration/dyndns" element={<DynDnsConfig />} />
            <Route path="/configuration/global-dns" element={<GlobalDnsConfig />} />
            <Route path="/configuration/webui" element={<WebuiConfig />} />
            <Route path="/configuration/apprise" element={<AppriseConfig />} />
          </Routes>
        </Suspense>
      </Layout>
    </BrowserRouter>
  );
}

export default App;
