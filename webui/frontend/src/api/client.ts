/**
 * API client with Axios
 */
import axios, { AxiosInstance } from 'axios';
import type { LoginRequest, LoginResponse, HistoricalDataPoint } from '../types/metrics';
import type {
  NotificationRule,
  NotificationRuleCreate,
  NotificationRuleUpdate,
  NotificationHistory,
  NotificationParameterMetadata,
  NotificationTestResponse,
  AppriseServiceInfo,
  AppriseService,
  AppriseServiceCreate,
  AppriseServiceUpdate,
} from '../types/notifications';

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
  async getFastfetch(): Promise<{ text: string }> {
    const response = await this.client.get<{ text: string }>('/api/system/fastfetch');
    return response.data;
  }

  // GitHub stats
  async getGitHubStats(): Promise<{ stars: number; forks: number }> {
    const response = await this.client.get<{ stars: number; forks: number }>('/api/system/github-stats');
    return response.data;
  }

  // Documentation
  async getDocumentation(): Promise<{ content: string }> {
    const response = await this.client.get<{ content: string }>('/api/system/documentation');
    return response.data;
  }

  // CAKE Traffic Shaping
  async getCakeStatus(): Promise<{ enabled: boolean; interface?: string }> {
    const response = await this.client.get<{ enabled: boolean; interface?: string }>('/api/cake/status');
    return response.data;
  }

  async getCurrentCakeStats(): Promise<any> {
    const response = await this.client.get('/api/cake/current');
    return response.data;
  }

  // Notification rules
  async getNotificationRules(): Promise<NotificationRule[]> {
    const response = await this.client.get<NotificationRule[]>('/api/notifications/rules');
    return response.data;
  }

  async getNotificationParameters(): Promise<NotificationParameterMetadata[]> {
    const response = await this.client.get<NotificationParameterMetadata[]>('/api/notifications/parameters');
    return response.data;
  }

  async createNotificationRule(payload: NotificationRuleCreate): Promise<NotificationRule> {
    const response = await this.client.post<NotificationRule>('/api/notifications/rules', payload);
    return response.data;
  }

  async updateNotificationRule(ruleId: number, payload: NotificationRuleUpdate): Promise<NotificationRule> {
    const response = await this.client.put<NotificationRule>(`/api/notifications/rules/${ruleId}`, payload);
    return response.data;
  }

  async deleteNotificationRule(ruleId: number): Promise<void> {
    await this.client.delete(`/api/notifications/rules/${ruleId}`);
  }

  async getNotificationHistory(ruleId: number, limit: number = 50): Promise<NotificationHistory> {
    const response = await this.client.get<NotificationHistory>(`/api/notifications/rules/${ruleId}/history`, {
      params: { limit },
    });
    return response.data;
  }

  async testNotificationRule(ruleId: number): Promise<NotificationTestResponse> {
    const response = await this.client.post<NotificationTestResponse>(`/api/notifications/rules/${ruleId}/test`, {});
    return response.data;
  }

  // Apprise Notifications
  async getAppriseStatus(): Promise<{ enabled: boolean }> {
    const response = await this.client.get<{ enabled: boolean }>('/api/apprise/status');
    return response.data;
  }

  async getAppriseServices(): Promise<AppriseServiceInfo[]> {
    const response = await this.client.get<AppriseServiceInfo[]>('/api/apprise/services');
    return response.data;
  }

  async getAppriseService(id: number): Promise<AppriseService> {
    const response = await this.client.get<AppriseService>(`/api/apprise/services/${id}`);
    return response.data;
  }

  async createAppriseService(service: AppriseServiceCreate): Promise<AppriseService> {
    const response = await this.client.post<AppriseService>('/api/apprise/services', service);
    return response.data;
  }

  async updateAppriseService(id: number, service: AppriseServiceUpdate): Promise<AppriseService> {
    const response = await this.client.put<AppriseService>(`/api/apprise/services/${id}`, service);
    return response.data;
  }

  async deleteAppriseService(id: number): Promise<{ message: string }> {
    const response = await this.client.delete<{ message: string }>(`/api/apprise/services/${id}`);
    return response.data;
  }

  async testAppriseServiceById(serviceId: number): Promise<{ success: boolean; message: string; details?: string }> {
    const response = await this.client.post<{ success: boolean; message: string; details?: string }>(`/api/apprise/services/${serviceId}/test`);
    return response.data;
  }

  async getAppriseConfig(): Promise<{
    enabled: boolean;
    services_count: number;
    config_file_exists: boolean;
    services?: string[];
    error?: string;
  }> {
    const response = await this.client.get('/api/apprise/config');
    return response.data;
  }

  async sendAppriseNotification(
    body: string,
    title?: string,
    notificationType?: string
  ): Promise<{ success: boolean; message: string; details?: string }> {
    const response = await this.client.post<{ success: boolean; message: string; details?: string }>('/api/apprise/notify', {
      body,
      title,
      notification_type: notificationType,
    });
    return response.data;
  }

  async testAppriseService(serviceIndex: number): Promise<{ success: boolean; message: string; details?: string }> {
    const response = await this.client.post<{ success: boolean; message: string; details?: string }>(`/api/apprise/test/${serviceIndex}`);
    return response.data;
  }

  async sendAppriseNotificationToService(
    serviceIndex: number,
    body: string,
    title?: string,
    notificationType?: string
  ): Promise<{ success: boolean; message: string; details?: string }> {
    const response = await this.client.post<{ success: boolean; message: string; details?: string }>(
      `/api/apprise/send/${serviceIndex}`,
      {
        body,
        title,
        notification_type: notificationType,
      }
    );
    return response.data;
  }

  async sendAppriseNotificationToServiceById(
    serviceId: number,
    body: string,
    title?: string,
    notificationType?: string
  ): Promise<{ success: boolean; message: string; details?: string }> {
    const response = await this.client.post<{ success: boolean; message: string; details?: string }>(
      `/api/apprise/services/${serviceId}/send`,
      {
        body,
        title,
        notification_type: notificationType,
      }
    );
    return response.data;
  }

  async getCakeHistory(
    range: string = '1h',
    interfaceName?: string
  ): Promise<{ interface: string; data: any[] }> {
    const params: Record<string, string> = { range };
    if (interfaceName) params.interface = interfaceName;
    const response = await this.client.get<{ interface: string; data: any[] }>('/api/cake/history', {
      params,
    });
    return response.data;
  }
}

export const apiClient = new APIClient();

