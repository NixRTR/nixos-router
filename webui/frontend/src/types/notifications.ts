export type ComparisonOperator = 'gt' | 'lt';

export interface NotificationParameterConfigOption {
  label: string;
  value: string;
}

export interface NotificationParameterConfigField {
  name: string;
  label: string;
  field_type: 'text' | 'select';
  description?: string;
  options?: NotificationParameterConfigOption[];
}

export interface NotificationParameterMetadata {
  type: string;
  label: string;
  unit?: string | null;
  description?: string | null;
  requires_config: boolean;
  config_fields: NotificationParameterConfigField[];
  variables: string[];
}

export interface NotificationRuleBase {
  name: string;
  enabled: boolean;
  parameter_type: string;
  parameter_config?: Record<string, string | number | null>;
  threshold_info?: number | null;
  threshold_warning?: number | null;
  threshold_failure?: number | null;
  comparison_operator: ComparisonOperator;
  duration_seconds: number;
  cooldown_seconds: number;
  apprise_service_indices: number[];
  message_template: string;
}

export interface NotificationRule extends NotificationRuleBase {
  id: number;
  created_at: string;
  updated_at: string;
  current_level?: string | null;
  last_notification_at?: string | null;
  last_notification_level?: string | null;
}

export type NotificationRuleCreate = NotificationRuleBase;

export type NotificationRuleUpdate = Partial<NotificationRuleBase> & {
  apprise_service_indices?: number[];
};

export interface NotificationHistoryRecord {
  id: number;
  rule_id: number;
  timestamp: string;
  level: string;
  value: number;
  message?: string | null;
  sent_successfully: boolean;
}

export interface NotificationHistory {
  rule_id: number;
  items: NotificationHistoryRecord[];
}

export interface NotificationTestResponse {
  success: boolean;
  level: string;
  value: number;
  message: string;
  error?: string | null;
}

export interface AppriseServiceInfo {
  id: number;
  name: string;
  description?: string | null;
  enabled: boolean;
}

export interface AppriseService {
  id: number;
  name: string;
  description?: string | null;
  url: string;
  original_secret_string?: string | null;
  enabled: boolean;
  created_at: string;
  updated_at: string;
}

export interface AppriseServiceCreate {
  name: string;
  description?: string | null;
  url: string;
}

export interface AppriseServiceUpdate {
  name?: string;
  description?: string | null;
  url?: string;
  enabled?: boolean;
}

