import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
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

function App() {
  return (
    <BrowserRouter basename={import.meta.env.VITE_BASE_PATH || '/'}>
      <Layout>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/installation" element={<Installation />} />
          <Route path="/installation/" element={<Navigate to="/installation" replace />} />
          <Route path="/upgrading" element={<Upgrading />} />
          <Route path="/upgrading/" element={<Navigate to="/upgrading" replace />} />
          <Route path="/verification" element={<Verification />} />
          <Route path="/verification/" element={<Navigate to="/verification" replace />} />
          <Route path="/configuration" element={<Configuration />} />
          <Route path="/configuration/" element={<Navigate to="/configuration" replace />} />
          <Route path="/configuration/system" element={<SystemConfig />} />
          <Route path="/configuration/system/" element={<Navigate to="/configuration/system" replace />} />
          <Route path="/configuration/wan" element={<WanConfig />} />
          <Route path="/configuration/wan/" element={<Navigate to="/configuration/wan" replace />} />
          <Route path="/configuration/lan-bridges" element={<LanBridgesConfig />} />
          <Route path="/configuration/lan-bridges/" element={<Navigate to="/configuration/lan-bridges" replace />} />
          <Route path="/configuration/homelab" element={<HomelabConfig />} />
          <Route path="/configuration/homelab/" element={<Navigate to="/configuration/homelab" replace />} />
          <Route path="/configuration/lan" element={<LanConfig />} />
          <Route path="/configuration/lan/" element={<Navigate to="/configuration/lan" replace />} />
          <Route path="/configuration/port-forwarding" element={<PortForwardingConfig />} />
          <Route path="/configuration/port-forwarding/" element={<Navigate to="/configuration/port-forwarding" replace />} />
          <Route path="/configuration/dyndns" element={<DynDnsConfig />} />
          <Route path="/configuration/dyndns/" element={<Navigate to="/configuration/dyndns" replace />} />
          <Route path="/configuration/global-dns" element={<GlobalDnsConfig />} />
          <Route path="/configuration/global-dns/" element={<Navigate to="/configuration/global-dns" replace />} />
          <Route path="/configuration/webui" element={<WebuiConfig />} />
          <Route path="/configuration/webui/" element={<Navigate to="/configuration/webui" replace />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  );
}

export default App;
