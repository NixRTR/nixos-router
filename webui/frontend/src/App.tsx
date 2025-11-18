/**
 * Main App component with routing
 */
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Login } from './components/auth/Login';
import { Dashboard } from './pages/Dashboard';
import { Network } from './pages/Network';
import { Clients } from './pages/Clients';
import { DeviceUsage } from './pages/DeviceUsage';
import { ConnectionDetails } from './pages/ConnectionDetails';
import { System } from './pages/System';

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const token = localStorage.getItem('access_token');
  return token ? <>{children}</> : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/dashboard"
          element={
            <ProtectedRoute>
              <Dashboard />
            </ProtectedRoute>
          }
        />
        <Route
          path="/network"
          element={
            <ProtectedRoute>
              <Network />
            </ProtectedRoute>
          }
        />
        <Route
          path="/devices"
          element={
            <ProtectedRoute>
              <Clients />
            </ProtectedRoute>
          }
        />
        <Route
          path="/device-usage"
          element={
            <ProtectedRoute>
              <DeviceUsage />
            </ProtectedRoute>
          }
        />
        <Route
          path="/device-usage/:ipAddress"
          element={
            <ProtectedRoute>
              <ConnectionDetails sourcePage="device-usage" />
            </ProtectedRoute>
          }
        />
        <Route
          path="/devices/:ipAddress"
          element={
            <ProtectedRoute>
              <ConnectionDetails sourcePage="devices" />
            </ProtectedRoute>
          }
        />
        <Route
          path="/system"
          element={
            <ProtectedRoute>
              <System />
            </ProtectedRoute>
          }
        />
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

