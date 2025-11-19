import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Link } from 'react-router-dom';

interface MarkdownContentProps {
  content: string;
}

export function MarkdownContent({ content }: MarkdownContentProps) {
  return (
    <article className="format format-blue dark:format-invert max-w-none">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          // Transform internal links (starting with /) to use React Router Link
          a: ({ href, children, ...props }) => {
            // Check if it's an internal link (starts with / and not an external URL)
            if (href && href.startsWith('/') && !href.startsWith('//')) {
              return (
                <Link to={href} {...props}>
                  {children}
                </Link>
              );
            }
            // External links - open in new tab
            return (
              <a href={href} target="_blank" rel="noopener noreferrer" {...props}>
                {children}
              </a>
            );
          },
        }}
      >
        {content}
      </ReactMarkdown>
    </article>
  );
}

