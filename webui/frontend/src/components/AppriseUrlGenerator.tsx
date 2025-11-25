/**
 * Apprise URL Generator Component
 * Allows users to generate Apprise notification service URLs through a form
 * Supports 30+ popular notification services
 */
import { useState } from 'react';
import { Button, Label, TextInput, Select, Alert, Modal, Textarea } from 'flowbite-react';
import { HiClipboard, HiCheckCircle } from 'react-icons/hi';
import { apiClient } from '../api/client';

type ServiceType = 
  // Email
  | 'email' 
  // Chat/Messaging
  | 'discord' | 'slack' | 'telegram' | 'matrix' | 'mattermost' | 'rocketchat' | 'msteams' | 'googlechat' | 'zulip' | 'line'
  // Push Notifications
  | 'pushover' | 'pushbullet' | 'gotify' | 'ntfy' | 'prowl' | 'join'
  // Home Automation
  | 'homeassistant'
  // SMS
  | 'twilio'
  // Cloud Services
  | 'awssns' | 'gcm' | 'fcm'
  // Webhooks
  | 'webhook' | 'json'
  // Other
  | 'ifttt' | 'xmpp' | 'kodi' | 'apprise';

interface ServiceConfig {
  [key: string]: string | number | boolean;
}

type EmailProvider = 
  | 'gmail'
  | 'yahoo'
  | 'hotmail'
  | 'live'
  | 'fastmail'
  | 'zoho'
  | 'yandex'
  | 'sendgrid'
  | 'qq'
  | '163'
  | 'custom';

interface AppriseUrlGeneratorProps {
  onServiceSaved?: () => void;
}

export function AppriseUrlGenerator({ onServiceSaved }: AppriseUrlGeneratorProps = {}) {
  const [serviceType, setServiceType] = useState<ServiceType | ''>('');
  const [config, setConfig] = useState<ServiceConfig>({});
  const [generatedUrl, setGeneratedUrl] = useState<string>('');
  const [copied, setCopied] = useState(false);
  const [saveModalOpen, setSaveModalOpen] = useState(false);
  const [saveName, setSaveName] = useState('');
  const [saveDescription, setSaveDescription] = useState('');
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [emailProvider, setEmailProvider] = useState<EmailProvider>('custom');

  const serviceTypes: { value: ServiceType; label: string; category?: string }[] = [
    // Email
    { value: 'email', label: 'Email (SMTP)', category: 'Email' },
    
    // Chat/Messaging
    { value: 'discord', label: 'Discord', category: 'Chat' },
    { value: 'slack', label: 'Slack', category: 'Chat' },
    { value: 'telegram', label: 'Telegram', category: 'Chat' },
    { value: 'matrix', label: 'Matrix', category: 'Chat' },
    { value: 'mattermost', label: 'Mattermost', category: 'Chat' },
    { value: 'rocketchat', label: 'Rocket.Chat', category: 'Chat' },
    { value: 'msteams', label: 'Microsoft Teams', category: 'Chat' },
    { value: 'googlechat', label: 'Google Chat', category: 'Chat' },
    { value: 'zulip', label: 'Zulip', category: 'Chat' },
    { value: 'line', label: 'Line', category: 'Chat' },
    
    // Push Notifications
    { value: 'pushover', label: 'Pushover', category: 'Push' },
    { value: 'pushbullet', label: 'Pushbullet', category: 'Push' },
    { value: 'gotify', label: 'Gotify', category: 'Push' },
    { value: 'ntfy', label: 'ntfy', category: 'Push' },
    { value: 'prowl', label: 'Prowl', category: 'Push' },
    { value: 'join', label: 'Join', category: 'Push' },
    
    // Home Automation
    { value: 'homeassistant', label: 'Home Assistant', category: 'Home Automation' },
    
    // SMS
    { value: 'twilio', label: 'Twilio (SMS)', category: 'SMS' },
    
    // Cloud Services
    { value: 'awssns', label: 'AWS SNS', category: 'Cloud' },
    { value: 'gcm', label: 'Google Cloud Messaging', category: 'Cloud' },
    { value: 'fcm', label: 'Firebase Cloud Messaging', category: 'Cloud' },
    
    // Webhooks
    { value: 'webhook', label: 'Generic Webhook', category: 'Webhook' },
    { value: 'json', label: 'JSON Webhook', category: 'Webhook' },
    
    // Other
    { value: 'ifttt', label: 'IFTTT', category: 'Other' },
    { value: 'xmpp', label: 'XMPP', category: 'Other' },
    { value: 'kodi', label: 'Kodi', category: 'Other' },
    { value: 'apprise', label: 'Apprise API', category: 'Other' },
  ];

  const urlEncode = (str: string): string => {
    return encodeURIComponent(str);
  };

  const generateUrl = () => {
    if (!serviceType) return;

    let url = '';

    switch (serviceType) {
      case 'email': {
        const username = String(config.username || '');
        const password = String(config.password || '');
        const to = String(config.to || '');
        const from = String(config.from || username);
        
        // Handle built-in email providers
        if (emailProvider !== 'custom') {
          const providerDomains: Record<EmailProvider, string> = {
            gmail: 'gmail.com',
            yahoo: 'yahoo.com',
            hotmail: 'hotmail.com',
            live: 'live.com',
            fastmail: 'fastmail.com',
            zoho: 'zoho.com',
            yandex: 'yandex.com',
            sendgrid: 'sendgrid.com',
            qq: 'qq.com',
            '163': '163.com',
            custom: '',
          };
          
          const domain = providerDomains[emailProvider];
          
          // For built-in providers, use mailto:// (secure is implied)
          if (emailProvider === 'sendgrid') {
            // SendGrid requires from parameter
            const fromEmail = from || username;
            url = `mailto://${urlEncode(username)}:${urlEncode(password)}@${domain}?from=${urlEncode(fromEmail)}`;
          } else {
            url = `mailto://${urlEncode(username)}:${urlEncode(password)}@${domain}`;
          }
        } else {
          // Custom SMTP server
          const smtpHost = String(config.smtpHost || '');
          const port = String(config.port || '587');
          const scheme = port === '465' ? 'mailtos' : 'mailto';
          url = `${scheme}://${urlEncode(username)}:${urlEncode(password)}@${smtpHost}:${port}?to=${urlEncode(to)}&from=${urlEncode(from)}`;
        }
        break;
      }

      case 'homeassistant': {
        const host = String(config.host || '');
        const port = String(config.port || (config.useHttps ? '443' : '8123'));
        const token = String(config.token || '');
        const useHttps = Boolean(config.useHttps);
        const scheme = useHttps ? 'hassios' : 'hassio';
        url = `${scheme}://${host}:${port}/${token}`;
        break;
      }

      case 'discord': {
        const webhookId = String(config.webhookId || '');
        const webhookToken = String(config.webhookToken || '');
        url = `discord://${webhookId}/${webhookToken}`;
        break;
      }

      case 'slack': {
        const tokenA = String(config.tokenA || '');
        const tokenB = String(config.tokenB || '');
        const tokenC = String(config.tokenC || '');
        url = `slack://${tokenA}/${tokenB}/${tokenC}`;
        break;
      }

      case 'telegram': {
        const botToken = String(config.botToken || '');
        const chatId = String(config.chatId || '');
        url = `tgram://${botToken}/${chatId}`;
        break;
      }

      case 'ntfy': {
        const topic = String(config.topic || '');
        const server = String(config.server || 'ntfy.sh');
        if (config.username && config.password) {
          const username = String(config.username);
          const password = String(config.password);
          url = `ntfy://${urlEncode(username)}:${urlEncode(password)}@${server}/${topic}`;
        } else {
          url = `ntfy://${server}/${topic}`;
        }
        break;
      }

      case 'pushover': {
        const userKey = String(config.userKey || '');
        const token = String(config.token || '');
        url = `pover://${userKey}@${token}`;
        break;
      }

      case 'pushbullet': {
        const token = String(config.token || '');
        const deviceId = String(config.deviceId || '');
        if (deviceId) {
          url = `pbul://${token}/${deviceId}`;
        } else {
          url = `pbul://${token}`;
        }
        break;
      }

      case 'gotify': {
        const host = String(config.host || '');
        const token = String(config.token || '');
        const port = String(config.port || '80');
        const useHttps = Boolean(config.useHttps);
        const scheme = useHttps ? 'gotifys' : 'gotify';
        url = `${scheme}://${host}:${port}/${token}`;
        break;
      }

      case 'matrix': {
        const host = String(config.host || '');
        const token = String(config.token || '');
        const room = String(config.room || '');
        const useHttps = Boolean(config.useHttps);
        const scheme = useHttps ? 'matrixs' : 'matrix';
        if (room) {
          url = `${scheme}://${host}/${room}?token=${urlEncode(token)}`;
        } else {
          url = `${scheme}://${host}?token=${urlEncode(token)}`;
        }
        break;
      }

      case 'mattermost': {
        const host = String(config.host || '');
        const token = String(config.token || '');
        const channel = String(config.channel || '');
        const useHttps = Boolean(config.useHttps);
        const scheme = useHttps ? 'mmosts' : 'mmost';
        if (channel) {
          url = `${scheme}://${host}/${channel}?token=${urlEncode(token)}`;
        } else {
          url = `${scheme}://${host}?token=${urlEncode(token)}`;
        }
        break;
      }

      case 'rocketchat': {
        const host = String(config.host || '');
        const user = String(config.user || '');
        const password = String(config.password || '');
        const channel = String(config.channel || '');
        const useHttps = Boolean(config.useHttps);
        const scheme = useHttps ? 'rockets' : 'rocket';
        if (channel) {
          url = `${scheme}://${urlEncode(user)}:${urlEncode(password)}@${host}/${channel}`;
        } else {
          url = `${scheme}://${urlEncode(user)}:${urlEncode(password)}@${host}`;
        }
        break;
      }

      case 'msteams': {
        const webhookUrl = String(config.webhookUrl || '');
        if (webhookUrl.startsWith('http')) {
          url = `msteams://${webhookUrl.replace(/^https?:\/\//, '')}`;
        } else {
          url = `msteams://${webhookUrl}`;
        }
        break;
      }

      case 'googlechat': {
        const webhookUrl = String(config.webhookUrl || '');
        if (webhookUrl.startsWith('http')) {
          url = `gchat://${webhookUrl.replace(/^https?:\/\//, '')}`;
        } else {
          url = `gchat://${webhookUrl}`;
        }
        break;
      }

      case 'zulip': {
        const host = String(config.host || '');
        const botEmail = String(config.botEmail || '');
        const botKey = String(config.botKey || '');
        const stream = String(config.stream || '');
        const topic = String(config.topic || '');
        const useHttps = Boolean(config.useHttps);
        const scheme = useHttps ? 'zulips' : 'zulip';
        let queryParams = `bot=${urlEncode(botEmail)}&key=${urlEncode(botKey)}`;
        if (stream) queryParams += `&stream=${urlEncode(stream)}`;
        if (topic) queryParams += `&topic=${urlEncode(topic)}`;
        url = `${scheme}://${host}?${queryParams}`;
        break;
      }

      case 'line': {
        const token = String(config.token || '');
        url = `line://${token}`;
        break;
      }

      case 'prowl': {
        const apikey = String(config.apikey || '');
        const providerKey = String(config.providerKey || '');
        if (providerKey) {
          url = `prowl://${apikey}@${providerKey}`;
        } else {
          url = `prowl://${apikey}`;
        }
        break;
      }

      case 'join': {
        const deviceId = String(config.deviceId || '');
        const apikey = String(config.apikey || '');
        url = `join://${deviceId}?apikey=${urlEncode(apikey)}`;
        break;
      }

      case 'twilio': {
        const accountSid = String(config.accountSid || '');
        const authToken = String(config.authToken || '');
        const fromNumber = String(config.fromNumber || '');
        const toNumber = String(config.toNumber || '');
        url = `twilio://${accountSid}:${urlEncode(authToken)}@${fromNumber}/${toNumber}`;
        break;
      }

      case 'awssns': {
        const region = String(config.region || 'us-east-1');
        const topicArn = String(config.topicArn || '');
        const accessKeyId = String(config.accessKeyId || '');
        const secretAccessKey = String(config.secretAccessKey || '');
        url = `sns://${urlEncode(accessKeyId)}:${urlEncode(secretAccessKey)}@${region}/${topicArn}`;
        break;
      }

      case 'gcm': {
        const projectId = String(config.projectId || '');
        const apiKey = String(config.apiKey || '');
        const registrationId = String(config.registrationId || '');
        url = `gcm://${urlEncode(apiKey)}@${projectId}/${registrationId}`;
        break;
      }

      case 'fcm': {
        const projectId = String(config.projectId || '');
        const apikey = String(config.apikey || '');
        const deviceToken = String(config.deviceToken || '');
        url = `fcm://${urlEncode(apikey)}@${projectId}/${deviceToken}`;
        break;
      }

      case 'webhook': {
        const urlValue = String(config.url || '');
        const method = String(config.method || 'POST').toUpperCase();
        if (urlValue.startsWith('http')) {
          url = `webhook${method === 'GET' ? 's' : ''}://${urlValue.replace(/^https?:\/\//, '')}`;
        } else {
          url = `webhook${method === 'GET' ? 's' : ''}://${urlValue}`;
        }
        break;
      }

      case 'json': {
        const urlValue = String(config.url || '');
        if (urlValue.startsWith('http')) {
          url = `json://${urlValue.replace(/^https?:\/\//, '')}`;
        } else {
          url = `json://${urlValue}`;
        }
        break;
      }

      case 'ifttt': {
        const webhookId = String(config.webhookId || '');
        const eventName = String(config.eventName || '');
        url = `ifttt://${webhookId}/${eventName}`;
        break;
      }

      case 'xmpp': {
        const user = String(config.user || '');
        const password = String(config.password || '');
        const host = String(config.host || '');
        const target = String(config.target || '');
        if (target) {
          url = `xmpp://${urlEncode(user)}:${urlEncode(password)}@${host}/${target}`;
        } else {
          url = `xmpp://${urlEncode(user)}:${urlEncode(password)}@${host}`;
        }
        break;
      }

      case 'kodi': {
        const host = String(config.host || '');
        const port = String(config.port || '8080');
        const user = String(config.user || '');
        const password = String(config.password || '');
        if (user && password) {
          url = `kodi://${urlEncode(user)}:${urlEncode(password)}@${host}:${port}`;
        } else {
          url = `kodi://${host}:${port}`;
        }
        break;
      }

      case 'apprise': {
        const host = String(config.host || '');
        const port = String(config.port || '8000');
        const token = String(config.token || '');
        const useHttps = Boolean(config.useHttps);
        const scheme = useHttps ? 'apprises' : 'apprise';
        if (token) {
          url = `${scheme}://${host}:${port}/${token}`;
        } else {
          url = `${scheme}://${host}:${port}`;
        }
        break;
      }
    }

    setGeneratedUrl(url);
    setCopied(false);
  };

  const copyToClipboard = async () => {
    if (generatedUrl) {
      await navigator.clipboard.writeText(generatedUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleConfigChange = (field: string, value: string | boolean) => {
    setConfig(prev => ({ ...prev, [field]: value }));
  };

  const resetForm = () => {
    setServiceType('');
    setConfig({});
    setGeneratedUrl('');
    setCopied(false);
  };

  const renderServiceForm = () => {
    if (!serviceType) return null;

    switch (serviceType) {
      case 'email':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="emailProvider">Email Provider</Label>
              <Select
                id="emailProvider"
                value={emailProvider}
                onChange={(e) => {
                  setEmailProvider(e.target.value as EmailProvider);
                  // Clear config when switching providers
                  setConfig({});
                }}
              >
                <option value="custom">Custom SMTP Server</option>
                <option value="gmail">Gmail</option>
                <option value="yahoo">Yahoo</option>
                <option value="hotmail">Hotmail</option>
                <option value="live">Live.com</option>
                <option value="fastmail">Fastmail</option>
                <option value="zoho">Zoho</option>
                <option value="yandex">Yandex</option>
                <option value="sendgrid">SendGrid</option>
                <option value="qq">QQ Mail</option>
                <option value="163">163 Mail</option>
              </Select>
            </div>

            {/* Provider-specific notes */}
            {emailProvider === 'gmail' && (
              <Alert color="info">
                <div className="text-sm">
                  <strong>Note:</strong> Google users using 2-Step Verification will be required to generate an{' '}
                  <a 
                    href="https://myaccount.google.com/apppasswords" 
                    target="_blank" 
                    rel="noopener noreferrer"
                    className="text-blue-600 dark:text-blue-400 underline"
                  >
                    app password
                  </a>
                  {' '}that you can use in the password field.
                </div>
              </Alert>
            )}

            {emailProvider === 'yahoo' && (
              <Alert color="info">
                <div className="text-sm">
                  <strong>Note:</strong> Yahoo users will be required to generate an{' '}
                  <a 
                    href="https://login.yahoo.com/account/security/app-passwords" 
                    target="_blank" 
                    rel="noopener noreferrer"
                    className="text-blue-600 dark:text-blue-400 underline"
                  >
                    app password
                  </a>
                  {' '}that you can use in the password field.
                </div>
              </Alert>
            )}

            {emailProvider === 'fastmail' && (
              <Alert color="info">
                <div className="text-sm">
                  <strong>Note:</strong> Fastmail users are required to generate a custom App password before connecting. 
                  You must assign the <strong>SMTP</strong> option to the new App you generate. 
                  This Fastmail plugin supports 116 domains - just make sure you identify the email address you're using when building the URL.
                </div>
              </Alert>
            )}

            {emailProvider === 'custom' && (
              <>
                <div>
                  <Label htmlFor="smtpHost">SMTP Host</Label>
                  <TextInput
                    id="smtpHost"
                    type="text"
                    placeholder="smtp.gmail.com"
                    value={String(config.smtpHost || '')}
                    onChange={(e) => handleConfigChange('smtpHost', e.target.value)}
                  />
                </div>
                <div>
                  <Label htmlFor="port">Port</Label>
                  <TextInput
                    id="port"
                    type="text"
                    placeholder="587"
                    value={String(config.port || '587')}
                    onChange={(e) => handleConfigChange('port', e.target.value)}
                  />
                  <p className="text-sm text-gray-500 mt-1">
                    Use 465 for SSL/TLS, 587 for STARTTLS
                  </p>
                </div>
                <div>
                  <Label htmlFor="to">To (Recipient Email)</Label>
                  <TextInput
                    id="to"
                    type="email"
                    placeholder="recipient@example.com"
                    value={String(config.to || '')}
                    onChange={(e) => handleConfigChange('to', e.target.value)}
                  />
                </div>
              </>
            )}

            <div>
              <Label htmlFor="username">
                {emailProvider === 'custom' ? 'Username' : 'Email Address'}
              </Label>
              <TextInput
                id="username"
                type="text"
                placeholder={emailProvider === 'custom' ? 'user@example.com' : 'user@provider.com'}
                value={String(config.username || '')}
                onChange={(e) => handleConfigChange('username', e.target.value)}
              />
            </div>

            <div>
              <Label htmlFor="password">
                {emailProvider === 'gmail' || emailProvider === 'yahoo' || emailProvider === 'fastmail' 
                  ? 'App Password' 
                  : 'Password'}
              </Label>
              <TextInput
                id="password"
                type="password"
                placeholder={
                  emailProvider === 'gmail' || emailProvider === 'yahoo' || emailProvider === 'fastmail'
                    ? 'App password (not your regular password)'
                    : 'Your password'
                }
                value={String(config.password || '')}
                onChange={(e) => handleConfigChange('password', e.target.value)}
              />
            </div>

            {emailProvider === 'sendgrid' && (
              <div>
                <Label htmlFor="from">From Email (Required for SendGrid)</Label>
                <TextInput
                  id="from"
                  type="email"
                  placeholder="noreply@your-validated-domain.com"
                  value={String(config.from || '')}
                  onChange={(e) => handleConfigChange('from', e.target.value)}
                />
                <p className="text-sm text-gray-500 mt-1">
                  Must use a validated domain from your SendGrid account
                </p>
              </div>
            )}

            {emailProvider === 'custom' && (
              <div>
                <Label htmlFor="from">From (Sender Email - Optional)</Label>
                <TextInput
                  id="from"
                  type="email"
                  placeholder="sender@example.com"
                  value={String(config.from || '')}
                  onChange={(e) => handleConfigChange('from', e.target.value)}
                />
                <p className="text-sm text-gray-500 mt-1">
                  Defaults to username if not provided
                </p>
              </div>
            )}
          </div>
        );

      case 'homeassistant':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">Home Assistant Host</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="homeassistant.local"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="port">Port</Label>
              <TextInput
                id="port"
                type="text"
                placeholder="8123"
                value={String(config.port || '')}
                onChange={(e) => handleConfigChange('port', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Default: 8123 (HTTP) or 443 (HTTPS)
              </p>
            </div>
            <div>
              <Label htmlFor="token">Long-lived Access Token</Label>
              <TextInput
                id="token"
                type="password"
                placeholder="Enter access credential"
                value={String(config.token || '')}
                onChange={(e) => handleConfigChange('token', e.target.value)}
              />
            </div>
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="useHttps"
                checked={Boolean(config.useHttps)}
                onChange={(e) => handleConfigChange('useHttps', e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="useHttps">Use HTTPS</Label>
            </div>
          </div>
        );

      case 'discord':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="webhookId">Webhook ID</Label>
              <TextInput
                id="webhookId"
                type="text"
                placeholder="123456789012345678"
                value={String(config.webhookId || '')}
                onChange={(e) => handleConfigChange('webhookId', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="webhookToken">Webhook Token</Label>
              <TextInput
                id="webhookToken"
                type="password"
                placeholder="Enter webhook credential"
                value={String(config.webhookToken || '')}
                onChange={(e) => handleConfigChange('webhookToken', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get these from Discord: Server Settings → Integrations → Webhooks
              </p>
            </div>
          </div>
        );

      case 'slack':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="tokenA">Token A</Label>
              <TextInput
                id="tokenA"
                type="password"
                placeholder="Enter first credential"
                value={String(config.tokenA || '')}
                onChange={(e) => handleConfigChange('tokenA', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="tokenB">Token B</Label>
              <TextInput
                id="tokenB"
                type="password"
                placeholder="Enter second credential"
                value={String(config.tokenB || '')}
                onChange={(e) => handleConfigChange('tokenB', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="tokenC">Token C</Label>
              <TextInput
                id="tokenC"
                type="password"
                placeholder="Enter third credential"
                value={String(config.tokenC || '')}
                onChange={(e) => handleConfigChange('tokenC', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get credentials from Slack: Apps → Your App → OAuth & Permissions
              </p>
            </div>
          </div>
        );

      case 'telegram':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="botToken">Bot Token</Label>
              <TextInput
                id="botToken"
                type="password"
                placeholder="Enter bot credential from @BotFather"
                value={String(config.botToken || '')}
                onChange={(e) => handleConfigChange('botToken', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from @BotFather on Telegram
              </p>
            </div>
            <div>
              <Label htmlFor="chatId">Chat ID</Label>
              <TextInput
                id="chatId"
                type="text"
                placeholder="123456789"
                value={String(config.chatId || '')}
                onChange={(e) => handleConfigChange('chatId', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Your Telegram user ID or group ID
              </p>
            </div>
          </div>
        );

      case 'ntfy':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="server">Server</Label>
              <TextInput
                id="server"
                type="text"
                placeholder="ntfy.sh"
                value={String(config.server || 'ntfy.sh')}
                onChange={(e) => handleConfigChange('server', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Default: ntfy.sh (public server)
              </p>
            </div>
            <div>
              <Label htmlFor="topic">Topic</Label>
              <TextInput
                id="topic"
                type="text"
                placeholder="my-topic"
                value={String(config.topic || '')}
                onChange={(e) => handleConfigChange('topic', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Topic name (no spaces, use hyphens)
              </p>
            </div>
            <div>
              <Label htmlFor="username">Username (Optional)</Label>
              <TextInput
                id="username"
                type="text"
                placeholder="username"
                value={String(config.username || '')}
                onChange={(e) => handleConfigChange('username', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="password">Password (Optional)</Label>
              <TextInput
                id="password"
                type="password"
                placeholder="password"
                value={String(config.password || '')}
                onChange={(e) => handleConfigChange('password', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Only required for private topics
              </p>
            </div>
          </div>
        );

      case 'pushover':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="userKey">User Key</Label>
              <TextInput
                id="userKey"
                type="text"
                placeholder="Enter user key"
                value={String(config.userKey || '')}
                onChange={(e) => handleConfigChange('userKey', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from pushover.net
              </p>
            </div>
            <div>
              <Label htmlFor="token">Application Token</Label>
              <TextInput
                id="token"
                type="password"
                placeholder="Enter application token"
                value={String(config.token || '')}
                onChange={(e) => handleConfigChange('token', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Create an application at pushover.net
              </p>
            </div>
          </div>
        );

      case 'pushbullet':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="token">Access Token</Label>
              <TextInput
                id="token"
                type="password"
                placeholder="Enter access token"
                value={String(config.token || '')}
                onChange={(e) => handleConfigChange('token', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from pushbullet.com → Settings → Access Tokens
              </p>
            </div>
            <div>
              <Label htmlFor="deviceId">Device ID (Optional)</Label>
              <TextInput
                id="deviceId"
                type="text"
                placeholder="device_iden"
                value={String(config.deviceId || '')}
                onChange={(e) => handleConfigChange('deviceId', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Leave empty to send to all devices
              </p>
            </div>
          </div>
        );

      case 'gotify':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">Gotify Server Host</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="gotify.example.com"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="port">Port</Label>
              <TextInput
                id="port"
                type="text"
                placeholder="80"
                value={String(config.port || '80')}
                onChange={(e) => handleConfigChange('port', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="token">Application Token</Label>
              <TextInput
                id="token"
                type="password"
                placeholder="Enter application token"
                value={String(config.token || '')}
                onChange={(e) => handleConfigChange('token', e.target.value)}
              />
            </div>
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="useHttps"
                checked={Boolean(config.useHttps)}
                onChange={(e) => handleConfigChange('useHttps', e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="useHttps">Use HTTPS</Label>
            </div>
          </div>
        );

      case 'matrix':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">Matrix Server</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="matrix.example.com"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="token">Access Token</Label>
              <TextInput
                id="token"
                type="password"
                placeholder="Enter access token"
                value={String(config.token || '')}
                onChange={(e) => handleConfigChange('token', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="room">Room ID (Optional)</Label>
              <TextInput
                id="room"
                type="text"
                placeholder="!roomid:example.com"
                value={String(config.room || '')}
                onChange={(e) => handleConfigChange('room', e.target.value)}
              />
            </div>
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="useHttps"
                checked={Boolean(config.useHttps)}
                onChange={(e) => handleConfigChange('useHttps', e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="useHttps">Use HTTPS</Label>
            </div>
          </div>
        );

      case 'mattermost':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">Mattermost Server</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="mattermost.example.com"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="token">Personal Access Token</Label>
              <TextInput
                id="token"
                type="password"
                placeholder="Enter access token"
                value={String(config.token || '')}
                onChange={(e) => handleConfigChange('token', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="channel">Channel Name (Optional)</Label>
              <TextInput
                id="channel"
                type="text"
                placeholder="general"
                value={String(config.channel || '')}
                onChange={(e) => handleConfigChange('channel', e.target.value)}
              />
            </div>
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="useHttps"
                checked={Boolean(config.useHttps)}
                onChange={(e) => handleConfigChange('useHttps', e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="useHttps">Use HTTPS</Label>
            </div>
          </div>
        );

      case 'rocketchat':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">Rocket.Chat Server</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="rocketchat.example.com"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="user">Username</Label>
              <TextInput
                id="user"
                type="text"
                placeholder="bot_user"
                value={String(config.user || '')}
                onChange={(e) => handleConfigChange('user', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="password">Password</Label>
              <TextInput
                id="password"
                type="password"
                placeholder="Enter password"
                value={String(config.password || '')}
                onChange={(e) => handleConfigChange('password', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="channel">Channel (Optional)</Label>
              <TextInput
                id="channel"
                type="text"
                placeholder="#general"
                value={String(config.channel || '')}
                onChange={(e) => handleConfigChange('channel', e.target.value)}
              />
            </div>
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="useHttps"
                checked={Boolean(config.useHttps)}
                onChange={(e) => handleConfigChange('useHttps', e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="useHttps">Use HTTPS</Label>
            </div>
          </div>
        );

      case 'msteams':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="webhookUrl">Webhook URL</Label>
              <TextInput
                id="webhookUrl"
                type="text"
                placeholder="https://outlook.office.com/webhook/..."
                value={String(config.webhookUrl || '')}
                onChange={(e) => handleConfigChange('webhookUrl', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from Teams: Channel → Connectors → Incoming Webhook
              </p>
            </div>
          </div>
        );

      case 'googlechat':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="webhookUrl">Webhook URL</Label>
              <TextInput
                id="webhookUrl"
                type="text"
                placeholder="https://chat.googleapis.com/v1/spaces/..."
                value={String(config.webhookUrl || '')}
                onChange={(e) => handleConfigChange('webhookUrl', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from Google Chat: Space → Configure Webhooks
              </p>
            </div>
          </div>
        );

      case 'zulip':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">Zulip Server</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="zulip.example.com"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="botEmail">Bot Email</Label>
              <TextInput
                id="botEmail"
                type="email"
                placeholder="bot@example.com"
                value={String(config.botEmail || '')}
                onChange={(e) => handleConfigChange('botEmail', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="botKey">Bot API Key</Label>
              <TextInput
                id="botKey"
                type="password"
                placeholder="Enter bot API key"
                value={String(config.botKey || '')}
                onChange={(e) => handleConfigChange('botKey', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="stream">Stream Name (Optional)</Label>
              <TextInput
                id="stream"
                type="text"
                placeholder="general"
                value={String(config.stream || '')}
                onChange={(e) => handleConfigChange('stream', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="topic">Topic (Optional)</Label>
              <TextInput
                id="topic"
                type="text"
                placeholder="notifications"
                value={String(config.topic || '')}
                onChange={(e) => handleConfigChange('topic', e.target.value)}
              />
            </div>
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="useHttps"
                checked={Boolean(config.useHttps)}
                onChange={(e) => handleConfigChange('useHttps', e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="useHttps">Use HTTPS</Label>
            </div>
          </div>
        );

      case 'line':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="token">Channel Access Token</Label>
              <TextInput
                id="token"
                type="password"
                placeholder="Enter channel access token"
                value={String(config.token || '')}
                onChange={(e) => handleConfigChange('token', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from Line Developers Console
              </p>
            </div>
          </div>
        );

      case 'prowl':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="apikey">API Key</Label>
              <TextInput
                id="apikey"
                type="password"
                placeholder="Enter API key"
                value={String(config.apikey || '')}
                onChange={(e) => handleConfigChange('apikey', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from prowlapp.com
              </p>
            </div>
            <div>
              <Label htmlFor="providerKey">Provider Key (Optional)</Label>
              <TextInput
                id="providerKey"
                type="password"
                placeholder="Enter provider key"
                value={String(config.providerKey || '')}
                onChange={(e) => handleConfigChange('providerKey', e.target.value)}
              />
            </div>
          </div>
        );

      case 'join':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="deviceId">Device ID</Label>
              <TextInput
                id="deviceId"
                type="text"
                placeholder="device_iden"
                value={String(config.deviceId || '')}
                onChange={(e) => handleConfigChange('deviceId', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from joinjoaomgcd.app → My Devices
              </p>
            </div>
            <div>
              <Label htmlFor="apikey">API Key</Label>
              <TextInput
                id="apikey"
                type="password"
                placeholder="Enter API key"
                value={String(config.apikey || '')}
                onChange={(e) => handleConfigChange('apikey', e.target.value)}
              />
            </div>
          </div>
        );

      case 'twilio':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="accountSid">Account SID</Label>
              <TextInput
                id="accountSid"
                type="text"
                placeholder="ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
                value={String(config.accountSid || '')}
                onChange={(e) => handleConfigChange('accountSid', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="authToken">Auth Token</Label>
              <TextInput
                id="authToken"
                type="password"
                placeholder="Enter auth token"
                value={String(config.authToken || '')}
                onChange={(e) => handleConfigChange('authToken', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="fromNumber">From Phone Number</Label>
              <TextInput
                id="fromNumber"
                type="text"
                placeholder="+1234567890"
                value={String(config.fromNumber || '')}
                onChange={(e) => handleConfigChange('fromNumber', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Your Twilio phone number (E.164 format)
              </p>
            </div>
            <div>
              <Label htmlFor="toNumber">To Phone Number</Label>
              <TextInput
                id="toNumber"
                type="text"
                placeholder="+1234567890"
                value={String(config.toNumber || '')}
                onChange={(e) => handleConfigChange('toNumber', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Recipient phone number (E.164 format)
              </p>
            </div>
          </div>
        );

      case 'awssns':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="region">AWS Region</Label>
              <TextInput
                id="region"
                type="text"
                placeholder="us-east-1"
                value={String(config.region || 'us-east-1')}
                onChange={(e) => handleConfigChange('region', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="topicArn">Topic ARN</Label>
              <TextInput
                id="topicArn"
                type="text"
                placeholder="arn:aws:sns:us-east-1:123456789012:MyTopic"
                value={String(config.topicArn || '')}
                onChange={(e) => handleConfigChange('topicArn', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="accessKeyId">Access Key ID</Label>
              <TextInput
                id="accessKeyId"
                type="text"
                placeholder="Enter access key ID"
                value={String(config.accessKeyId || '')}
                onChange={(e) => handleConfigChange('accessKeyId', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="secretAccessKey">Secret Access Key</Label>
              <TextInput
                id="secretAccessKey"
                type="password"
                placeholder="Enter secret access key"
                value={String(config.secretAccessKey || '')}
                onChange={(e) => handleConfigChange('secretAccessKey', e.target.value)}
              />
            </div>
          </div>
        );

      case 'gcm':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="projectId">Project ID</Label>
              <TextInput
                id="projectId"
                type="text"
                placeholder="my-project-id"
                value={String(config.projectId || '')}
                onChange={(e) => handleConfigChange('projectId', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="apiKey">API Key</Label>
              <TextInput
                id="apiKey"
                type="password"
                placeholder="Enter API key"
                value={String(config.apiKey || '')}
                onChange={(e) => handleConfigChange('apiKey', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="registrationId">Registration ID</Label>
              <TextInput
                id="registrationId"
                type="text"
                placeholder="Enter registration ID"
                value={String(config.registrationId || '')}
                onChange={(e) => handleConfigChange('registrationId', e.target.value)}
              />
            </div>
          </div>
        );

      case 'fcm':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="projectId">Project ID</Label>
              <TextInput
                id="projectId"
                type="text"
                placeholder="my-project-id"
                value={String(config.projectId || '')}
                onChange={(e) => handleConfigChange('projectId', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="apikey">Server Key</Label>
              <TextInput
                id="apikey"
                type="password"
                placeholder="Enter server key"
                value={String(config.apikey || '')}
                onChange={(e) => handleConfigChange('apikey', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="deviceToken">Device Token</Label>
              <TextInput
                id="deviceToken"
                type="text"
                placeholder="Enter device token"
                value={String(config.deviceToken || '')}
                onChange={(e) => handleConfigChange('deviceToken', e.target.value)}
              />
            </div>
          </div>
        );

      case 'webhook':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="url">Webhook URL</Label>
              <TextInput
                id="url"
                type="text"
                placeholder="https://example.com/webhook"
                value={String(config.url || '')}
                onChange={(e) => handleConfigChange('url', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="method">HTTP Method</Label>
              <Select
                id="method"
                value={String(config.method || 'POST')}
                onChange={(e) => handleConfigChange('method', e.target.value)}
              >
                <option value="POST">POST</option>
                <option value="GET">GET</option>
                <option value="PUT">PUT</option>
                <option value="PATCH">PATCH</option>
              </Select>
            </div>
          </div>
        );

      case 'json':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="url">JSON Webhook URL</Label>
              <TextInput
                id="url"
                type="text"
                placeholder="https://example.com/webhook"
                value={String(config.url || '')}
                onChange={(e) => handleConfigChange('url', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                URL that accepts JSON POST requests
              </p>
            </div>
          </div>
        );

      case 'ifttt':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="webhookId">Webhook ID</Label>
              <TextInput
                id="webhookId"
                type="text"
                placeholder="Enter webhook ID"
                value={String(config.webhookId || '')}
                onChange={(e) => handleConfigChange('webhookId', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Get from ifttt.com → My Applets → Webhooks → Settings
              </p>
            </div>
            <div>
              <Label htmlFor="eventName">Event Name</Label>
              <TextInput
                id="eventName"
                type="text"
                placeholder="notification"
                value={String(config.eventName || '')}
                onChange={(e) => handleConfigChange('eventName', e.target.value)}
              />
            </div>
          </div>
        );

      case 'xmpp':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">XMPP Server</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="xmpp.example.com"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="user">Username (JID)</Label>
              <TextInput
                id="user"
                type="text"
                placeholder="user@example.com"
                value={String(config.user || '')}
                onChange={(e) => handleConfigChange('user', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="password">Password</Label>
              <TextInput
                id="password"
                type="password"
                placeholder="Enter password"
                value={String(config.password || '')}
                onChange={(e) => handleConfigChange('password', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="target">Target JID (Optional)</Label>
              <TextInput
                id="target"
                type="text"
                placeholder="recipient@example.com"
                value={String(config.target || '')}
                onChange={(e) => handleConfigChange('target', e.target.value)}
              />
              <p className="text-sm text-gray-500 mt-1">
                Leave empty to send to yourself
              </p>
            </div>
          </div>
        );

      case 'kodi':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">Kodi Host</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="192.168.1.100"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="port">Port</Label>
              <TextInput
                id="port"
                type="text"
                placeholder="8080"
                value={String(config.port || '8080')}
                onChange={(e) => handleConfigChange('port', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="user">Username (Optional)</Label>
              <TextInput
                id="user"
                type="text"
                placeholder="kodi"
                value={String(config.user || '')}
                onChange={(e) => handleConfigChange('user', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="password">Password (Optional)</Label>
              <TextInput
                id="password"
                type="password"
                placeholder="Enter password"
                value={String(config.password || '')}
                onChange={(e) => handleConfigChange('password', e.target.value)}
              />
            </div>
          </div>
        );

      case 'apprise':
        return (
          <div className="space-y-4">
            <div>
              <Label htmlFor="host">Apprise API Host</Label>
              <TextInput
                id="host"
                type="text"
                placeholder="apprise.example.com"
                value={String(config.host || '')}
                onChange={(e) => handleConfigChange('host', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="port">Port</Label>
              <TextInput
                id="port"
                type="text"
                placeholder="8000"
                value={String(config.port || '8000')}
                onChange={(e) => handleConfigChange('port', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="token">Token (Optional)</Label>
              <TextInput
                id="token"
                type="password"
                placeholder="Enter token"
                value={String(config.token || '')}
                onChange={(e) => handleConfigChange('token', e.target.value)}
              />
            </div>
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="useHttps"
                checked={Boolean(config.useHttps)}
                onChange={(e) => handleConfigChange('useHttps', e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="useHttps">Use HTTPS</Label>
            </div>
          </div>
        );

      default:
        return null;
    }
  };

  // Group services by category for better organization
  const groupedServices = serviceTypes.reduce((acc, service) => {
    const category = service.category || 'Other';
    if (!acc[category]) {
      acc[category] = [];
    }
    acc[category].push(service);
    return acc;
  }, {} as Record<string, typeof serviceTypes>);

  return (
    <div className="space-y-4">
        <div>
          <Label htmlFor="serviceType">Service Type</Label>
          <Select
            id="serviceType"
            value={serviceType}
            onChange={(e) => {
              setServiceType(e.target.value as ServiceType);
              setConfig({});
              setGeneratedUrl('');
            }}
          >
            <option value="">Select a service...</option>
            {Object.entries(groupedServices).map(([category, services]) => (
              <optgroup key={category} label={category}>
                {services.map((type) => (
                  <option key={type.value} value={type.value}>
                    {type.label}
                  </option>
                ))}
              </optgroup>
            ))}
          </Select>
        </div>

        {serviceType && (
          <>
            {renderServiceForm()}
            
            <div className="flex gap-2 pt-4">
              <Button onClick={generateUrl} color="blue">
                Generate URL
              </Button>
              <Button onClick={resetForm} color="gray" outline>
                Reset
              </Button>
            </div>
          </>
        )}

        {generatedUrl && (
          <div className="mt-4">
            <Label>Generated URL</Label>
            <div className="flex gap-2">
              <TextInput
                type="text"
                value={generatedUrl}
                readOnly
                className="font-mono text-sm"
              />
              <Button
                onClick={copyToClipboard}
                color={copied ? 'success' : 'gray'}
                size="sm"
              >
                {copied ? (
                  <>
                    <HiCheckCircle className="w-4 h-4 mr-1" />
                    Copied!
                  </>
                ) : (
                  <>
                    <HiClipboard className="w-4 h-4 mr-1" />
                    Copy
                  </>
                )}
              </Button>
              <Button
                onClick={() => {
                  setSaveModalOpen(true);
                  setSaveName('');
                  setSaveDescription('');
                  setSaveError(null);
                  setSaveSuccess(false);
                }}
                color="blue"
                size="sm"
              >
                Save Service
              </Button>
            </div>
            <Alert color="info" className="mt-2">
              <div className="text-sm">
                <strong>Note:</strong> You can save this service to the database for easier management, or copy it to store in secrets.yaml.
              </div>
            </Alert>
          </div>
        )}

        {/* Save Service Modal */}
        <Modal show={saveModalOpen} onClose={() => setSaveModalOpen(false)}>
          <Modal.Header>Save Apprise Service</Modal.Header>
          <Modal.Body>
            <div className="space-y-4">
              {saveError && (
                <Alert color="failure">
                  {saveError}
                </Alert>
              )}
              {saveSuccess && (
                <Alert color="success">
                  Service saved successfully!
                </Alert>
              )}
              <div>
                <Label htmlFor="saveName" value="Service Name *" />
                <TextInput
                  id="saveName"
                  value={saveName}
                  onChange={(e) => setSaveName(e.target.value)}
                  placeholder="e.g., Discord Notifications"
                  required
                  className="mt-1"
                />
              </div>
              <div>
                <Label htmlFor="saveDescription" value="Description (optional)" />
                <Textarea
                  id="saveDescription"
                  value={saveDescription}
                  onChange={(e) => setSaveDescription(e.target.value)}
                  placeholder="Optional description for this service"
                  rows={3}
                  className="mt-1"
                />
              </div>
              <div>
                <Label htmlFor="saveUrl" value="Service URL" />
                <TextInput
                  id="saveUrl"
                  readOnly
                  value={generatedUrl}
                  className="mt-1 font-mono text-sm"
                />
              </div>
            </div>
          </Modal.Body>
          <Modal.Footer>
            <Button
              color="blue"
              onClick={async () => {
                if (!saveName.trim()) {
                  setSaveError('Service name is required');
                  return;
                }
                setSaving(true);
                setSaveError(null);
                setSaveSuccess(false);
                try {
                  await apiClient.createAppriseService({
                    name: saveName.trim(),
                    description: saveDescription.trim() || null,
                    url: generatedUrl,
                  });
                  setSaveSuccess(true);
                  setTimeout(() => {
                    setSaveModalOpen(false);
                    setSaveName('');
                    setSaveDescription('');
                    setSaveSuccess(false);
                    // Call the callback if provided
                    if (onServiceSaved) {
                      onServiceSaved();
                    }
                  }, 1500);
                } catch (error: any) {
                  setSaveError(error.response?.data?.detail || error.message || 'Failed to save service');
                } finally {
                  setSaving(false);
                }
              }}
              disabled={saving || !saveName.trim()}
            >
              {saving ? 'Saving...' : 'Save'}
            </Button>
            <Button color="gray" onClick={() => setSaveModalOpen(false)}>
              Cancel
            </Button>
          </Modal.Footer>
        </Modal>
      </div>
  );
}
