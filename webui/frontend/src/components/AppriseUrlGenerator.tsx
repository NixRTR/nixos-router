/**
 * Apprise URL Generator Component
 * Allows users to generate Apprise notification service URLs through a form
 */
import { useState } from 'react';
import { Card, Button, Label, TextInput, Select, Alert } from 'flowbite-react';
import { HiClipboard, HiCheckCircle } from 'react-icons/hi';

type ServiceType = 'email' | 'homeassistant' | 'discord' | 'slack' | 'telegram' | 'ntfy';

interface ServiceConfig {
  [key: string]: string | number | boolean;
}

export function AppriseUrlGenerator() {
  const [serviceType, setServiceType] = useState<ServiceType | ''>('');
  const [config, setConfig] = useState<ServiceConfig>({});
  const [generatedUrl, setGeneratedUrl] = useState<string>('');
  const [copied, setCopied] = useState(false);

  const serviceTypes: { value: ServiceType; label: string }[] = [
    { value: 'email', label: 'Email (SMTP)' },
    { value: 'homeassistant', label: 'Home Assistant' },
    { value: 'discord', label: 'Discord' },
    { value: 'slack', label: 'Slack' },
    { value: 'telegram', label: 'Telegram' },
    { value: 'ntfy', label: 'ntfy' },
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
        const smtpHost = String(config.smtpHost || '');
        const port = String(config.port || '587');
        const to = String(config.to || '');
        const from = String(config.from || username);
        
        // Use mailtos:// for port 465 (SSL/TLS), mailto:// for others
        const scheme = port === '465' ? 'mailtos' : 'mailto';
        url = `${scheme}://${urlEncode(username)}:${urlEncode(password)}@${smtpHost}:${port}?to=${urlEncode(to)}&from=${urlEncode(from)}`;
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
              <Label htmlFor="username">Username</Label>
              <TextInput
                id="username"
                type="text"
                placeholder="user@example.com"
                value={String(config.username || '')}
                onChange={(e) => handleConfigChange('username', e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="password">Password</Label>
              <TextInput
                id="password"
                type="password"
                placeholder="Your password"
                value={String(config.password || '')}
                onChange={(e) => handleConfigChange('password', e.target.value)}
              />
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

      default:
        return null;
    }
  };

  return (
    <Card className="bg-gray-50 dark:bg-gray-800">
      <h3 className="text-xl font-bold mb-4">Apprise URL Generator</h3>
      
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
            {serviceTypes.map((type) => (
              <option key={type.value} value={type.value}>
                {type.label}
              </option>
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
            </div>
            <Alert color="info" className="mt-2">
              <div className="text-sm">
                <strong>Note:</strong> This URL contains sensitive information. 
                Store it securely in your secrets.yaml file.
              </div>
            </Alert>
          </div>
        )}
      </div>
    </Card>
  );
}

