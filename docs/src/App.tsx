import { BrowserRouter, Routes, Route, useLocation, useNavigate } from 'react-router-dom';
import { useEffect } from 'react';
import { Layout } from './components/Layout';
import { Home } from './pages/Home';
import { Installation } from './pages/Installation';
import { Upgrading } from './pages/Upgrading';
import { Verification } from './pages/Verification';
import { Configuration } from './pages/Configuration';
import { SystemConfig } from './pages/configuration/System';
import { WanConfig } from './pages/configuration/Wan';
import { LanBridgesConfig } from './pages/configuration/LanBridges';
import { HomelabConfig } from './pages/configuration/Homelab';
import { LanConfig } from './pages/configuration/Lan';
import { PortForwardingConfig } from './pages/configuration/PortForwarding';
import { DynDnsConfig } from './pages/configuration/DynDns';
import { GlobalDnsConfig } from './pages/configuration/GlobalDns';
import { WebuiConfig } from './pages/configuration/Webui';

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

function App() {
  return (
    <BrowserRouter basename={import.meta.env.VITE_BASE_PATH || '/docs/'}>
      <TrailingSlashHandler />
      <Layout>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/installation" element={<Installation />} />
          <Route path="/upgrading" element={<Upgrading />} />
          <Route path="/verification" element={<Verification />} />
          <Route path="/configuration" element={<Configuration />} />
          <Route path="/configuration/system" element={<SystemConfig />} />
          <Route path="/configuration/wan" element={<WanConfig />} />
          <Route path="/configuration/lan-bridges" element={<LanBridgesConfig />} />
          <Route path="/configuration/homelab" element={<HomelabConfig />} />
          <Route path="/configuration/lan" element={<LanConfig />} />
          <Route path="/configuration/port-forwarding" element={<PortForwardingConfig />} />
          <Route path="/configuration/dyndns" element={<DynDnsConfig />} />
          <Route path="/configuration/global-dns" element={<GlobalDnsConfig />} />
          <Route path="/configuration/webui" element={<WebuiConfig />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  );
}

export default App;
