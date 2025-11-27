/**
 * Main App component with routing
 */
import { lazy, Suspense } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Login } from './components/auth/Login';

// Lazy load pages for code splitting - reduces initial bundle size
const Dashboard = lazy(() => import('./pages/Dashboard').then(m => ({ default: m.Dashboard })));
const Network = lazy(() => import('./pages/Network').then(m => ({ default: m.Network })));
const Clients = lazy(() => import('./pages/Clients').then(m => ({ default: m.Clients })));
const DeviceUsage = lazy(() => import('./pages/DeviceUsage').then(m => ({ default: m.DeviceUsage })));
const ConnectionDetails = lazy(() => import('./pages/ConnectionDetails').then(m => ({ default: m.ConnectionDetails })));
const System = lazy(() => import('./pages/System').then(m => ({ default: m.System })));
const SystemInfo = lazy(() => import('./pages/SystemInfo').then(m => ({ default: m.SystemInfo })));
const Documentation = lazy(() => import('./pages/Documentation').then(m => ({ default: m.Documentation })));
const Speedtest = lazy(() => import('./pages/Speedtest').then(m => ({ default: m.Speedtest })));
const TrafficShaping = lazy(() => import('./pages/TrafficShaping').then(m => ({ default: m.TrafficShaping })));
const Notifications = lazy(() => import('./pages/Notifications').then(m => ({ default: m.Notifications })));
const Dns = lazy(() => import('./pages/Dns').then(m => ({ default: m.Dns })));
const Dhcp = lazy(() => import('./pages/Dhcp').then(m => ({ default: m.Dhcp })));

// Loading fallback component
const PageLoader = () => (
  <div className="flex items-center justify-center h-screen">
    <div className="text-gray-600 dark:text-gray-400">Loading...</div>
  </div>
);

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
              <Suspense fallback={<PageLoader />}>
              <Dashboard />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/network"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
              <Network />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/devices"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
              <Clients />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/device-usage"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <DeviceUsage />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/device-usage/:ipAddress"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <ConnectionDetails sourcePage="device-usage" />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/devices/:ipAddress"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <ConnectionDetails sourcePage="devices" />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/system"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
              <System />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/system-info"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <SystemInfo />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/documentation"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <Documentation />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/speedtest"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <Speedtest />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/traffic-shaping"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <TrafficShaping />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/notifications"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <Notifications />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/dns"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <Dns />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route
          path="/dhcp"
          element={
            <ProtectedRoute>
              <Suspense fallback={<PageLoader />}>
                <Dhcp />
              </Suspense>
            </ProtectedRoute>
          }
        />
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

