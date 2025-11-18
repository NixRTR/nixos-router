/**
 * API client with Axios
 */
import axios, { AxiosInstance } from 'axios';
import type { LoginRequest, LoginResponse, HistoricalDataPoint } from '../types/metrics';

const API_BASE_URL = import.meta.env.VITE_API_URL || '';

class APIClient {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    // Add request interceptor to inject JWT token
    this.client.interceptors.request.use(
      (config) => {
        const token = localStorage.getItem('access_token');
        if (token) {
          config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
      },
      (error) => Promise.reject(error)
    );

    // Add response interceptor to handle errors
    this.client.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error.response?.status === 401) {
          // Token expired or invalid
          localStorage.removeItem('access_token');
          localStorage.removeItem('username');
          window.location.href = '/login';
        }
        return Promise.reject(error);
      }
    );
  }

  // Authentication
  async login(credentials: LoginRequest): Promise<LoginResponse> {
    const response = await this.client.post<LoginResponse>('/api/auth/login', credentials);
    return response.data;
  }

  async logout(): Promise<void> {
    await this.client.post('/api/auth/logout');
    localStorage.removeItem('access_token');
    localStorage.removeItem('username');
  }

  async getCurrentUser(): Promise<{ username: string }> {
    const response = await this.client.get<{ username: string }>('/api/auth/me');
    return response.data;
  }

  // Historical data
  async getSystemHistory(
    start?: Date,
    end?: Date,
    interval?: number
  ): Promise<HistoricalDataPoint[]> {
    const params: Record<string, string> = {};
    if (start) params.start = start.toISOString();
    if (end) params.end = end.toISOString();
    if (interval) params.interval = interval.toString();

    const response = await this.client.get<HistoricalDataPoint[]>('/api/history/system', {
      params,
    });
    return response.data;
  }

  async getInterfaceHistory(
    interfaceName: string,
    start?: Date,
    end?: Date,
    interval?: number
  ): Promise<HistoricalDataPoint[]> {
    const params: Record<string, string> = {};
    if (start) params.start = start.toISOString();
    if (end) params.end = end.toISOString();
    if (interval) params.interval = interval.toString();

    const response = await this.client.get<HistoricalDataPoint[]>(
      `/api/history/interface/${interfaceName}`,
      { params }
    );
    return response.data;
  }

  async getBandwidthHistory(
    network: string,
    period: '1h' | '24h' | '7d' | '30d' = '1h'
  ): Promise<HistoricalDataPoint[]> {
    const response = await this.client.get<HistoricalDataPoint[]>(
      `/api/history/bandwidth/${network}`,
      { params: { period } }
    );
    return response.data;
  }

  // Health check
  async healthCheck(): Promise<{ status: string; active_connections: number }> {
    const response = await this.client.get<{ status: string; active_connections: number }>(
      '/api/health'
    );
    return response.data;
  }

  // Client bandwidth
  async getCurrentClientBandwidth(): Promise<any[]> {
    const response = await this.client.get('/api/bandwidth/clients/current');
    return response.data;
  }

  async getClientBandwidthHistory(
    macAddress: string,
    range: string = '1h',
    interval: string = 'raw'
  ): Promise<any> {
    const response = await this.client.get(`/api/bandwidth/clients/${macAddress}`, {
      params: { range, interval },
    });
    return response.data;
  }

  async getBulkClientBandwidthHistory(
    range: string = '1h',
    interval: string = 'raw'
  ): Promise<Record<string, any>> {
    const response = await this.client.get('/api/bandwidth/clients/history/bulk', {
      params: { range, interval },
    });
    return response.data;
  }

  async getCurrentInterfaceStats(): Promise<Record<string, any>> {
    const response = await this.client.get('/api/bandwidth/interfaces/current');
    return response.data;
  }

  async getInterfaceTotals(timeRange: string = '1h'): Promise<Record<string, any>> {
    const response = await this.client.get('/api/bandwidth/interfaces/totals', {
      params: { range: timeRange },
    });
    return response.data;
  }

  // Client connections
  async getClientConnections(
    clientIp: string,
    timeRange: string = '1h'
  ): Promise<any[]> {
    const response = await this.client.get(`/api/bandwidth/connections/${clientIp}/current`, {
      params: { range: timeRange },
    });
    return response.data;
  }

  async getConnectionHistory(
    clientIp: string,
    remoteIp: string,
    remotePort: number,
    timeRange: string = '1h',
    interval: string = 'raw'
  ): Promise<any> {
    const response = await this.client.get(`/api/bandwidth/connections/${clientIp}/history`, {
      params: {
        remote_ip: remoteIp,
        remote_port: remotePort,
        range: timeRange,
        interval,
      },
    });
    return response.data;
  }

  // System info
  async getFastfetch(): Promise<{ image: string }> {
    const response = await this.client.get<{ image: string }>('/api/system/fastfetch');
    return response.data;
  }
}

export const apiClient = new APIClient();

