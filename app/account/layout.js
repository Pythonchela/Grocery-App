import AccountShell from '../../components/account/AccountShell';

export const metadata = {
  title: 'My Account | Haatvia',
};

export default function AccountLayout({ children }) {
  return <AccountShell>{children}</AccountShell>;
}
